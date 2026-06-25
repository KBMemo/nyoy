# frozen_string_literal: true

class RefineImageJob < ApplicationJob
  queue_as :image_generation

  def perform(image_generation_id)
    generation = ImageGeneration.find(image_generation_id)
    draft = generation.drafts[generation.selected_draft_index]
    raise "選択したラフ案が見つかりません" unless draft

    generation.update!(status: "refining", image_started_at: Time.current, image_finished_at: nil)

    switch_model(generation)
    refine_image(generation, draft)

    generation.update!(status: "completed", image_finished_at: Time.current, finished_at: Time.current)
  rescue StandardError => e
    stamp_open_phases!(generation)
    generation&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  def switch_model(generation)
    switch = SdModelSwitcher.new
    switch.switch(generation.sd_model, lora: generation.switch_lora_name)
  end

  def refine_image(generation, draft)
    png_data = SdCppClient.new.img2img(
      prompt: generation.prompt,
      negative_prompt: NegativePromptResolver.for_generation(generation),
      init_image: draft.download,
      width: generation.width,
      height: generation.height,
      steps: generation.refine_steps_for_api,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: generation.sampler_name,
      vae_tiling: generation.vae_tiling,
      denoising_strength: generation.refine_denoising_strength,
      lora: generation.loras_for_api
    )

    generation.image.purge if generation.image.attached?
    generation.image.attach(
      io: StringIO.new(png_data),
      filename: "generation-#{generation.id}.png",
      content_type: "image/png"
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
