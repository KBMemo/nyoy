# frozen_string_literal: true

class InpaintMemoIllustrationJob < ApplicationJob
  queue_as :image_generation

  def perform(memo_illustration_id, mask_data:, inpaint_note: nil, inpaint_prompt_delta: nil, include_style_prefix: false, include_style_suffix: false, denoising_strength: nil, source_attachment_id: nil)
    illustration = MemoIllustration.find(memo_illustration_id)
    raise "部分修正できない状態です" unless illustration.inpaint_job_runnable?

    prompt_result = InpaintPromptBuilder.call(
      illustration: illustration,
      inpaint_note: inpaint_note,
      inpaint_prompt_delta: inpaint_prompt_delta,
      include_prefix: include_style_prefix,
      include_suffix: include_style_suffix
    )
    resolved_prompt = prompt_result.prompt

    illustration.update!(
      status: "inpainting",
      image_started_at: Time.current,
      image_finished_at: nil,
      error_message: nil
    )

    source = resolve_source_attachment(illustration, source_attachment_id)
    init_image = source.download
    mask = decode_mask(mask_data)
    width, height = png_dimensions(init_image)

    switch_model(illustration)

    png_data = SdCppClient.new.inpaint(
      prompt: resolved_prompt,
      negative_prompt: illustration.resolved_negative_prompt,
      init_image: init_image,
      mask: mask,
      width: width,
      height: height,
      steps: illustration.steps,
      cfg_scale: illustration.cfg_scale,
      seed: illustration.seed || -1,
      sampler_name: illustration.resolved_params["sampler_name"],
      denoising_strength: denoising_strength.to_f.positive? ? denoising_strength.to_f : MemoIllustration::DEFAULT_INPAINT_DENOISING_STRENGTH,
      lora: illustration.loras_for_api
    )

    sequence = illustration.inpainted_images.attachments.count + 1
    illustration.inpainted_images.attach(
      io: StringIO.new(png_data),
      filename: "inpaint-#{illustration.id}-#{sequence}.png",
      content_type: "image/png",
      metadata: {
        sequence: sequence,
        denoising_strength: denoising_strength,
        inpaint_note: prompt_result.note_result&.original || inpaint_note.to_s.strip.presence,
        inpaint_note_translated: prompt_result.delta,
        inpaint_include_prefix: prompt_result.include_prefix,
        inpaint_include_suffix: prompt_result.include_suffix,
        inpaint_prompt: resolved_prompt
      }
    )

    illustration.update!(status: "completed", image_finished_at: Time.current)
  rescue StandardError => e
    stamp_open_phases!(illustration)
    illustration&.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def resolve_source_attachment(illustration, source_attachment_id)
    if source_attachment_id.present?
      attachment = illustration.inpainted_images.attachments.find_by(id: source_attachment_id)
      return attachment if attachment

      if illustration.image_attachment&.id == source_attachment_id.to_i
        return illustration.image_attachment
      end
    end

    illustration.default_inpaint_source_attachment
  end

  def decode_mask(mask_data)
    encoded = mask_data.to_s
    encoded = encoded.sub(/\Adata:image\/\w+;base64,/, "")
    data = Base64.decode64(encoded)
    raise "マスク画像が空です" if data.blank?

    data
  end

  def png_dimensions(png_data)
    image = Vips::Image.new_from_buffer(png_data, "")
    [image.width, image.height]
  end

  def switch_model(illustration)
    switch_key = illustration.resolved_params["switch_key"].presence || illustration.sd_model
    SdModelSwitcher.new.switch(switch_key)
  end

  def stamp_open_phases!(illustration)
    return unless illustration

    now = Time.current
    attrs = {}
    attrs[:image_finished_at] = now if illustration.image_started_at && !illustration.image_finished_at
    illustration.update!(attrs) if attrs.any?
  end
end
