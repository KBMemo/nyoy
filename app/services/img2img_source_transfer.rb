# frozen_string_literal: true

class Img2imgSourceTransfer
  Result = Struct.new(:blob, :filename, :content_type, :label, :settings, keyword_init: true) do
    def apply_to!(generation)
      generation.assign_attributes(settings) if settings.present?
    end
  end

  class Error < StandardError; end

  DEFAULT_DENOISING_STRENGTH = 0.55

  def self.call(**params)
    new(**params).call
  end

  def initialize(from_memo: nil, from_image_generation: nil, from_img2img: nil, attachment_id: nil, attachment: nil)
    @from_memo = from_memo
    @from_image_generation = from_image_generation
    @from_img2img = from_img2img
    @attachment_id = attachment_id
    @attachment = attachment
  end

  def call
    if @from_memo.present?
      from_memo_illustration(@from_memo)
    elsif @from_image_generation.present?
      from_image_generation_record(@from_image_generation)
    elsif @from_img2img.present?
      from_img2img_generation(@from_img2img)
    end
  end

  private

  def from_memo_illustration(id)
    illustration = MemoIllustration.find_by(id: id)
    raise Error, "メモイラストが見つかりません" unless illustration

    attachment = resolve_memo_attachment(illustration)
    raise Error, "転記できる画像がありません" unless attachment

    settings = memo_settings(illustration, attachment)
    Result.new(
      blob: attachment.blob,
      filename: attachment.filename.to_s,
      content_type: attachment.content_type,
      label: "#{illustration.inpainted_attachment?(attachment) ? illustration.inpainted_image_label(attachment) : '生成結果'}（メモイラスト ##{illustration.id}）",
      settings: settings
    )
  end

  def memo_settings(illustration, attachment)
    prompt = if illustration.inpainted_attachment?(attachment)
      illustration.inpaint_prompt_for(attachment).presence || illustration.positive_prompt
    else
      illustration.positive_prompt
    end

    denoising = attachment.metadata["denoising_strength"].presence
    denoising = denoising.to_f if denoising.present?

    {
      japanese_prompt: illustration.body,
      prompt: prompt,
      negative_prompt: illustration.resolved_negative_prompt,
      resolved_negative_prompt: illustration.resolved_negative_prompt,
      style_id: illustration.style_id,
      seed: illustration.seed,
      steps: illustration.steps,
      cfg_scale: illustration.cfg_scale,
      width: illustration.width,
      height: illustration.height,
      sd_model: illustration.sd_model,
      resolved_loras: illustration.resolved_loras,
      resolved_params: illustration.resolved_params,
      sampler_name: illustration.resolved_params["sampler_name"].presence || "euler_a",
      vae_tiling: illustration.resolved_params.fetch("vae_tiling", true),
      denoising_strength: denoising&.positive? ? denoising : DEFAULT_DENOISING_STRENGTH,
      use_source_dimensions: true
    }
  end

  def resolve_memo_attachment(illustration)
    if @attachment_id.present?
      attachment = illustration.inpainted_images.attachments.find_by(id: @attachment_id)
      return attachment if attachment
      return illustration.image_attachment if illustration.image_attachment&.id == @attachment_id.to_i
    end

    illustration.latest_display_attachment || illustration.image_attachment
  end

  def from_image_generation_record(id)
    generation = ImageGeneration.find_by(id: id)
    raise Error, "画像生成が見つかりません" unless generation

    attachment = resolve_image_generation_attachment(generation)
    raise Error, "転記できる画像がありません" unless attachment

    label = attachment_label(generation, attachment)
    Result.new(
      blob: attachment.blob,
      filename: attachment.filename.to_s,
      content_type: attachment.content_type,
      label: "#{label}（画像生成 ##{generation.id}）",
      settings: image_generation_settings(generation, attachment)
    )
  end

  def image_generation_settings(generation, attachment)
    refined = generation.refined_images.attachments.any? { |item| item.id == attachment.id }
    draft = generation.drafts.attachments.any? { |item| item.id == attachment.id }

    settings = {
      japanese_prompt: generation.japanese_prompt,
      prompt: generation.prompt,
      negative_prompt: generation.resolved_negative_prompt,
      resolved_negative_prompt: generation.resolved_negative_prompt,
      style_id: generation.style_id,
      aspect_ratio: generation.aspect_ratio,
      seed: generation.seed,
      cfg_scale: generation.cfg_scale,
      sampler_name: generation.sampler_name,
      vae_tiling: generation.vae_tiling,
      sd_model: generation.sd_model,
      resolved_loras: generation.resolved_loras,
      resolved_params: generation.resolved_params,
      loras: generation.loras,
      use_source_dimensions: true
    }

    if refined
      settings.merge!(
        steps: generation.refine_steps_for_api,
        denoising_strength: generation.refine_denoising_strength,
        width: generation.width,
        height: generation.height
      )
    elsif draft
      settings.merge!(
        steps: generation.draft_steps_for_api,
        denoising_strength: generation.refine_denoising_strength,
        width: generation.draft_width,
        height: generation.draft_height
      )
    else
      settings.merge!(
        steps: generation.steps,
        denoising_strength: generation.refine_denoising_strength,
        width: generation.width,
        height: generation.height
      )
    end

    settings
  end

  def from_img2img_generation(id)
    source = Img2imgGeneration.find_by(id: id)
    raise Error, "Img2Img 生成が見つかりません" unless source

    attachment = source.image_attachment || source.source_image_attachment
    raise Error, "転記できる画像がありません" unless attachment

    settings = img2img_settings(source)

    Result.new(
      blob: attachment.blob,
      filename: attachment.filename.to_s,
      content_type: attachment.content_type,
      label: "#{attachment == source.image_attachment ? '生成結果' : '元画像'}（Img2Img ##{source.id}）",
      settings: img2img_settings(source)
    )
  end

  def img2img_settings(source)
    {
      japanese_prompt: source.japanese_prompt,
      prompt: source.prompt,
      negative_prompt: source.negative_prompt.presence || source.resolved_negative_prompt,
      resolved_negative_prompt: source.resolved_negative_prompt,
      style_id: source.style_id,
      aspect_ratio: source.aspect_ratio,
      seed: source.seed,
      steps: source.steps,
      cfg_scale: source.cfg_scale,
      sampler_name: source.sampler_name,
      vae_tiling: source.vae_tiling,
      sd_model: source.sd_model,
      resolved_loras: source.resolved_loras,
      resolved_params: source.resolved_params,
      loras: source.loras,
      denoising_strength: source.denoising_strength,
      width: source.width,
      height: source.height,
      use_source_dimensions: source.use_source_dimensions
    }
  end

  def resolve_image_generation_attachment(generation)
    token = @attachment.presence || @attachment_id

    if token.to_s.start_with?("draft_")
      index = token.to_s.delete_prefix("draft_").to_i
      generation.drafts.attachments.sort_by(&:created_at)[index]
    elsif token.to_s.start_with?("refined_")
      attachment_id = token.to_s.delete_prefix("refined_")
      generation.refined_images.attachments.find_by(id: attachment_id)
    elsif token.present?
      generation.refined_images.attachments.find_by(id: token) ||
        generation.drafts.attachments.find_by(id: token) ||
        generation.image_attachment
    else
      generation.latest_refined_attachment || generation.drafts.attachments.first || generation.image_attachment
    end
  end

  def attachment_label(generation, attachment)
    if generation.refined_images.attachments.any? { |item| item.id == attachment.id }
      generation.refined_image_label(attachment)
    elsif generation.drafts.attachments.any? { |item| item.id == attachment.id }
      index = generation.drafts.attachments.sort_by(&:created_at).index { |item| item.id == attachment.id }
      "ラフ案 #{index.to_i + 1}"
    else
      "画像"
    end
  end
end
