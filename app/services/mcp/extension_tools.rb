# frozen_string_literal: true

module Mcp
  module ExtensionTools
    module_function

    def available?
      sd_tools_available?
    end

    def sd_tools_available?
      NyoyConnectionStore.enabled?(:sd_cpp) && NyoyConnectionStore.url(:sd_cpp).present?
    end

    def mcp_tools
      return [] unless available?

      [
        list_prompt_styles_tool,
        generate_image_tool,
        get_image_generation_tool,
        refine_image_tool
      ]
    end

    def list_prompt_styles_tool
      MCP::Tool.define(
        name: "list_prompt_styles",
        description: "利用可能な画像生成スタイル（prompt_styles）の一覧を返す。generate_image の style_id 指定に使う。",
        input_schema: { type: "object", properties: {} },
        annotations: {
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true,
          open_world_hint: false
        }
      ) do |**|
        styles = PromptStyle.enabled.ordered.map do |style|
          {
            style_id: style.style_id,
            name: style.name,
            description: style.description
          }.compact
        end

        MCP::Tool::Response.new([{ type: "text", text: JSON.generate({ styles: styles }) }])
      end
    end

    def generate_image_tool
      MCP::Tool.define(
        name: "generate_image",
        description: "日本語プロンプトから Stable Diffusion 画像のラフ案を非同期生成する。返却された id で get_image_generation をポーリングする。",
        input_schema: {
          type: "object",
          properties: {
            japanese_prompt: { type: "string", description: "生成したい内容（日本語）" },
            style_id: { type: "string", description: "省略時は LLM が style を選択" },
            aspect_ratio: {
              type: "string",
              enum: StylePlanJsonSchema::ASPECT_RATIOS,
              description: "square / portrait / landscape。省略可"
            },
            style_plan_connection_key: {
              type: "string",
              description: "style 計画用 LLM 接続キー。省略時は AppSetting 既定"
            }
          },
          required: [ "japanese_prompt" ]
        },
        annotations: {
          read_only_hint: false,
          destructive_hint: false,
          idempotent_hint: false,
          open_world_hint: true
        }
      ) do |**kwargs|
        generation = Mcp::ExtensionTools.build_generation(**kwargs)
        unless generation.save
          return MCP::Tool::Response.new(
            [{ type: "text", text: JSON.generate({ error: generation.errors.full_messages.join(", ") }) }],
            error: true
          )
        end

        GenerateImageJob.perform_later(generation.id)

        MCP::Tool::Response.new([{
          type: "text",
          text: JSON.generate({
            id: generation.id,
            status: generation.status,
            show_path: Rails.application.routes.url_helpers.image_generation_path(generation),
            note: "get_image_generation でステータスを確認。awaiting_selection 後は refine_image でラフ案を仕上げ。"
          })
        }])
      end
    end

    def get_image_generation_tool
      MCP::Tool.define(
        name: "get_image_generation",
        description: "generate_image で開始した画像生成の進捗と結果概要を取得する。",
        input_schema: {
          type: "object",
          properties: {
            id: { type: "integer", description: "ImageGeneration の id" }
          },
          required: [ "id" ]
        },
        annotations: {
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true,
          open_world_hint: false
        }
      ) do |id:, **|
        generation = ImageGeneration.find_by(id: id)
        unless generation
          return MCP::Tool::Response.new(
            [{ type: "text", text: JSON.generate({ error: "ImageGeneration #{id} が見つかりません" }) }],
            error: true
          )
        end

        MCP::Tool::Response.new([{ type: "text", text: JSON.generate(Mcp::ExtensionTools.summary_for(generation)) }])
      end
    end

    def refine_image_tool
      MCP::Tool.define(
        name: "refine_image",
        description: "generate_image のラフ案を選択して仕上げ画像を非同期生成する。get_image_generation で completed を確認。",
        input_schema: {
          type: "object",
          properties: {
            id: { type: "integer", description: "ImageGeneration の id" },
            draft_index: { type: "integer", description: "選択するラフ案（0 始まり）" },
            refine_denoising_strength: { type: "number", description: "img2img の denoising strength（省略可）" },
            refine_steps: { type: "integer", description: "仕上げ steps（省略可）" },
            enable_hires: { type: "boolean", description: "hires を有効にする（省略可）" },
            hires_upscaler: { type: "string", enum: ImageGeneration::HIRES_UPSCALERS },
            hires_scale: { type: "number" },
            hires_steps: { type: "integer" },
            hires_denoising_strength: { type: "number" },
            refine_render_preset_id: { type: "integer", description: "RenderPreset(refine) の id" }
          },
          required: %w[id draft_index]
        },
        annotations: {
          read_only_hint: false,
          destructive_hint: false,
          idempotent_hint: false,
          open_world_hint: true
        }
      ) do |id:, draft_index:, **kwargs|
        generation = ImageGeneration.find_by(id: id)
        unless generation
          return Mcp::ExtensionTools.error_response("ImageGeneration #{id} が見つかりません")
        end
        unless generation.refineable?
          return Mcp::ExtensionTools.error_response("この生成は仕上げできません（status=#{generation.status}）")
        end
        unless draft_index.to_i.in?(0...generation.drafts.count)
          return Mcp::ExtensionTools.error_response("draft_index が範囲外です（0..#{generation.drafts.count - 1}）")
        end

        Mcp::ExtensionTools.apply_refine!(generation, draft_index: draft_index.to_i, **kwargs)
        RefineImageJob.perform_later(generation.id)

        MCP::Tool::Response.new([{
          type: "text",
          text: JSON.generate({
            id: generation.id,
            status: generation.status,
            selected_draft_index: generation.selected_draft_index,
            show_path: Rails.application.routes.url_helpers.image_generation_path(generation),
            note: "get_image_generation で completed を確認してください。"
          })
        }])
      end
    end

    def apply_refine!(generation, draft_index:, refine_render_preset_id: nil, refine_denoising_strength: nil,
                      refine_steps: nil, enable_hires: nil, hires_upscaler: nil, hires_scale: nil,
                      hires_steps: nil, hires_denoising_strength: nil, **)
      if refine_render_preset_id.present?
        RenderPreset.find_by(id: refine_render_preset_id)&.apply_refine_to(generation)
      end

      attrs = {
        selected_draft_index: draft_index,
        status: "refining",
        image_started_at: Time.current,
        image_finished_at: nil,
        finished_at: nil,
        error_message: nil
      }
      attrs[:refine_denoising_strength] = refine_denoising_strength if refine_denoising_strength.present?
      attrs[:refine_steps] = refine_steps if refine_steps.present?
      attrs[:enable_hires] = enable_hires unless enable_hires.nil?
      attrs[:hires_upscaler] = hires_upscaler if hires_upscaler.present?
      attrs[:hires_scale] = hires_scale if hires_scale.present?
      attrs[:hires_steps] = hires_steps if hires_steps.present?
      attrs[:hires_denoising_strength] = hires_denoising_strength if hires_denoising_strength.present?

      generation.update!(attrs)
      generation
    end

    def error_response(message)
      MCP::Tool::Response.new(
        [{ type: "text", text: JSON.generate({ error: message }) }],
        error: true
      )
    end

    def build_generation(japanese_prompt:, style_id: nil, aspect_ratio: nil, style_plan_connection_key: nil, **)
      generation = ImageGeneration.new(
        japanese_prompt: japanese_prompt,
        style_id: style_id.presence,
        aspect_ratio: aspect_ratio.presence,
        style_plan_connection_key: style_plan_connection_key.presence,
        width: 768,
        height: 768,
        steps: 22,
        cfg_scale: 6.0,
        sampler_name: "euler_a",
        vae_tiling: true,
        draft_batch_size: 4,
        refine_denoising_strength: 0.4,
        enable_hires: true,
        hires_upscaler: "Latent",
        hires_scale: 1.5,
        hires_denoising_strength: 0.35
      )
      RenderPreset.default_for_kind("draft")&.apply_draft_to(generation)
      RenderPreset.default_for_kind("refine")&.apply_refine_to(generation)
      generation
    end

    def summary_for(generation)
      draft_count = generation.drafts.attachments.size
      {
        id: generation.id,
        status: generation.status,
        status_label: generation.status_label,
        show_path: Rails.application.routes.url_helpers.image_generation_path(generation),
        japanese_prompt: generation.japanese_prompt,
        style_id: generation.style_id,
        style_label: generation.style_label,
        prompt: generation.prompt,
        error_message: generation.error_message,
        draft_count: draft_count,
        draft_indices: (0...draft_count).to_a,
        draft_urls: draft_urls_for(generation),
        selected_draft_index: generation.selected_draft_index,
        refined_count: generation.refined_images.attachments.size,
        in_progress: generation.in_progress?,
        awaiting_selection: generation.awaiting_selection?,
        refineable: generation.refineable?,
        completed: generation.status == "completed"
      }.compact
    end

    def draft_urls_for(generation)
      return [] unless generation.drafts.attached?

      url_options = Rails.application.config.action_mailer.default_url_options || {}
      generation.drafts.attachments.filter_map do |attachment|
        Rails.application.routes.url_helpers.rails_blob_url(attachment, **url_options)
      rescue StandardError
        nil
      end
    end
  end
end
