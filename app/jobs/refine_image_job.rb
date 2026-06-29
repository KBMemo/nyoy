# frozen_string_literal: true

class RefineImageJob < ApplicationJob
  queue_as :image_generation

  def perform(image_generation_id)
    generation = ImageGeneration.find(image_generation_id)
    draft = generation.drafts[generation.selected_draft_index]
    raise "選択したラフ案が見つかりません" unless draft

    generation.update!(status: "refining", image_started_at: Time.current, image_finished_at: nil)

    switch_model(generation)
    refined_png = refine_image(generation, draft)
    final_png = finalize_output(generation, refined_png)
    attach_final_image(generation, final_png)

    generation.update!(status: "completed", image_finished_at: Time.current, finished_at: Time.current)
  rescue StandardError => e
    stamp_open_phases!(generation)
    generation&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  def switch_model(generation)
    switch_key = generation.resolved_params["switch_key"].presence || generation.sd_model
    SdModelSwitcher.new.switch(switch_key)
  end

  def refine_image(generation, draft)
    SdCppClient.new.img2img(
      prompt: generation.prompt,
      negative_prompt: generation.resolved_negative_prompt,
      init_image: draft.download,
      width: generation.draft_width,
      height: generation.draft_height,
      steps: generation.refine_steps_for_api,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: generation.sampler_name,
      vae_tiling: generation.vae_tiling,
      denoising_strength: generation.refine_denoising_strength,
      lora: generation.loras_for_api
    )
  end

  def finalize_output(generation, refined_png)
    if generation.enable_hires?
      upscale_image(generation, refined_png)
    elsif generation.needs_output_upscale?
      ImageResizer.resize_png(
        refined_png,
        width: generation.width,
        height: generation.height
      )
    else
      refined_png
    end
  end

  def upscale_image(generation, init_image)
    SdCppClient.new.img2img(
      prompt: generation.prompt,
      negative_prompt: generation.resolved_negative_prompt,
      init_image: init_image,
      width: generation.draft_width,
      height: generation.draft_height,
      steps: generation.hires_steps_for_api,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: generation.sampler_name,
      vae_tiling: generation.vae_tiling,
      denoising_strength: generation.hires_denoising_strength,
      lora: generation.loras_for_api,
      enable_hr: true,
      hr_upscaler: generation.hires_upscaler,
      hr_scale: generation.hires_scale,
      hr_steps: generation.hires_steps_for_api,
      hr_denoising_strength: generation.hires_denoising_strength,
      hr_resize_x: generation.hires_target_width,
      hr_resize_y: generation.hires_target_height
    )
  end

  def attach_final_image(generation, png_data)
    sequence = generation.refined_images.attachments.count + 1
    draft_index = generation.selected_draft_index

    generation.refined_images.attach(
      io: StringIO.new(png_data),
      filename: "refined-#{generation.id}-#{sequence}.png",
      content_type: "image/png",
      metadata: { draft_index: draft_index, sequence: sequence }
    )
  end

  def stamp_open_phases!(generation)
    return unless generation

    now = Time.current
    attrs = {}
    attrs[:image_finished_at] = now if generation.image_started_at && !generation.image_finished_at
    generation.update!(attrs) if attrs.any?
  end
end
