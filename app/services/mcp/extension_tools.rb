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
        list_image_generation_options_tool,
        list_prompt_styles_tool,
        generate_image_tool,
        get_image_generation_tool,
        refine_image_tool
      ]
    end

    def list_image_generation_options_tool
      MCP::Tool.define(
        name: "list_image_generation_options",
        description: "generate_image の draft / direct 生成で使うスタイル、SD モデルプロファイル、direct 用プロンプトテンプレートを返す。",
        input_schema: { type: "object", properties: {} },
        annotations: {
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true,
          open_world_hint: false
        }
      ) do |**|
        MCP::Tool::Response.new([{ type: "text", text: JSON.generate(Mcp::ExtensionTools.image_generation_options) }])
      end
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

    def image_generation_options
      {
        generation_flows: ImageGeneration::GENERATION_FLOWS,
        styles: PromptStyle.enabled.ordered.map { |style| style_option(style) },
        sd_model_profiles: SdModelProfile.enabled.ordered.map { |profile| sd_model_profile_option(profile) },
        sd_prompt_templates: SdPromptTemplate.enabled.includes(:sd_model_profile).ordered.map { |template| sd_prompt_template_option(template) }
      }
    end

    def style_option(style)
      {
        style_id: style.style_id,
        name: style.name,
        description: style.description
      }.compact
    end

    def sd_model_profile_option(profile)
      {
        id: profile.id,
        key: profile.key,
        name: profile.name,
        family: profile.family,
        switch_key: profile.switch_key,
        cfg_scale_min: profile.cfg_scale_min,
        sampler_names: profile.family_sampler_names,
        default_params: profile.resolved_default_params
      }
    end

    def sd_prompt_template_option(template)
      {
        id: template.id,
        name: template.name,
        scope_label: template.scope_label,
        family: template.family,
        sd_model_profile_id: template.sd_model_profile_id,
        sd_model_profile_name: template.sd_model_profile&.name
      }.compact
    end

    def generate_image_tool
      MCP::Tool.define(
        name: "generate_image",
        description: "日本語プロンプトから Stable Diffusion 画像を非同期生成する。既定はラフ案生成。generation_flow=direct なら直接 txt2img 生成する。",
        input_schema: {
          type: "object",
          properties: {
            japanese_prompt: { type: "string", description: "生成したい内容（日本語）" },
            generation_flow: {
              type: "string",
              enum: ImageGeneration::GENERATION_FLOWS,
              description: "draft（既定）または direct"
            },
            sd_model_profile_id: {
              type: "integer",
              description: "direct 生成で使う SdModelProfile id（generation_flow=direct で必須）"
            },
            sd_prompt_template_id: {
              type: "integer",
              description: "direct 生成で使う SdPromptTemplate id（省略可）"
            },
            prompt: {
              type: "string",
              description: "direct 生成用 SD prompt。省略時は GenerateImageJob が日本語プロンプトから生成"
            },
            negative_prompt: {
              type: "string",
              description: "direct 生成用 negative prompt。省略可"
            },
            width: { type: "integer", description: "direct 生成幅。省略時はモデル既定" },
            height: { type: "integer", description: "direct 生成高さ。省略時はモデル既定" },
            steps: { type: "integer", description: "direct 生成 steps。省略時はモデル既定" },
            cfg_scale: { type: "number", description: "direct 生成 CFG scale。省略時はモデル既定" },
            sampler_name: { type: "string", description: "direct 生成 sampler。省略時はモデル既定" },
            seed: { type: "integer", description: "seed。省略時または -1 はランダム" },
            vae_tiling: { type: "boolean", description: "VAE tiling を使うか。省略時 true" },
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
            generation_flow: generation.generation_flow,
            show_path: Rails.application.routes.url_helpers.image_generation_path(generation),
            note: generation.direct_flow? ?
              "get_image_generation で completed を確認してください。" :
              "get_image_generation でステータスを確認。awaiting_selection 後は refine_image でラフ案を仕上げ。"
          })
        }])
      rescue ArgumentError => e
        Mcp::ExtensionTools.error_response(e.message)
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

    def build_generation(japanese_prompt:, generation_flow: nil, style_id: nil, aspect_ratio: nil,
                         style_plan_connection_key: nil, **kwargs)
      flow = generation_flow.to_s.presence || "draft"
      return build_direct_generation(japanese_prompt: japanese_prompt, style_plan_connection_key: style_plan_connection_key, **kwargs) if flow == "direct"
      raise ArgumentError, "generation_flow は draft または direct を指定してください" unless flow == "draft"

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

    def build_direct_generation(japanese_prompt:, sd_model_profile_id: nil, sd_prompt_template_id: nil,
                                prompt: nil, negative_prompt: nil, style_plan_connection_key: nil, **kwargs)
      profile = SdModelProfile.enabled.find_by(id: sd_model_profile_id)
      raise ArgumentError, "direct 生成には sd_model_profile_id が必要です" unless profile

      params = profile.resolved_default_params || {}
      generation = ImageGeneration.new(
        generation_flow: "direct",
        japanese_prompt: japanese_prompt,
        prompt: prompt.presence,
        negative_prompt: negative_prompt.presence,
        style_plan_connection_key: style_plan_connection_key.presence,
        sd_model_profile: profile,
        sd_prompt_template_id: sd_prompt_template_id.presence,
        width: direct_param(kwargs, params, :width, 768).to_i,
        height: direct_param(kwargs, params, :height, 768).to_i,
        steps: direct_param(kwargs, params, :steps, 24).to_i,
        cfg_scale: direct_param(kwargs, params, :cfg_scale, 6.0).to_f,
        sampler_name: direct_param(kwargs, params, :sampler_name, "euler_a").to_s,
        seed: kwargs[:seed],
        vae_tiling: kwargs.key?(:vae_tiling) ? kwargs[:vae_tiling] : true,
        loras: "[]",
        enable_hires: false
      )
      generation
    end

    def direct_param(kwargs, defaults, key, fallback)
      value = kwargs[key]
      value = defaults[key.to_s] if value.nil?
      value.nil? ? fallback : value
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
        generation_flow: generation.generation_flow,
        sd_model_profile_id: generation.sd_model_profile_id,
        sd_model_profile_name: generation.sd_model_profile&.name,
        prompt: generation.prompt,
        negative_prompt: generation.negative_prompt,
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
      generation.drafts.attachments.map do |attachment|
        Rails.application.routes.url_helpers.rails_blob_url(attachment, **url_options)
      rescue StandardError
        nil
      end
    end
  end
end
