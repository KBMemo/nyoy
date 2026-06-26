# frozen_string_literal: true

class GenerateImageJob < ApplicationJob
  queue_as :image_generation

  def perform(image_generation_id)
    generation = ImageGeneration.find(image_generation_id)
    generation.update!(started_at: Time.current, status: "preparing")

    switch_model(generation)
    prepare_prompt(generation)
    generate_drafts(generation)

    generation.update!(status: "awaiting_selection")
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

  def prepare_prompt(generation)
    return if generation.prompt.to_s.strip.present?

    generate_prompt_with_rag(generation)
  end

  def generate_prompt_with_rag(generation)
    generation.update!(status: "translating", prompt_started_at: Time.current)

    spec = PromptSpecGenerator.new(generation: generation).call
    spec.apply_to_generation!(generation)
    generation.update!(prompt_finished_at: Time.current)
  rescue PromptSpecGenerator::Error
    translate_prompt(generation)
  end

  def translate_prompt(generation)
    generation.update!(status: "translating", prompt_started_at: Time.current)

    prompt = SdPromptTranslator.new.translate(
      generation.japanese_prompt,
      skill: generation.prompt_skill
    )
    generation.update!(prompt: prompt, prompt_finished_at: Time.current)
  end

  def generate_drafts(generation)
    generation.update!(status: "drafting", image_started_at: Time.current)

    png_list = SdCppClient.new.txt2img(
      prompt: generation.prompt,
      negative_prompt: NegativePromptResolver.for_generation(generation),
      width: generation.width,
      height: generation.height,
      steps: generation.draft_steps_for_api,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: generation.sampler_name,
      vae_tiling: generation.vae_tiling,
      lora: generation.loras_for_api,
      batch_size: generation.draft_batch_size
    )

    generation.drafts.purge
    Array(png_list).each_with_index do |png_data, index|
      generation.drafts.attach(
        io: StringIO.new(png_data),
        filename: "draft-#{generation.id}-#{index}.png",
        content_type: "image/png"
      )
    end
    generation.update!(image_finished_at: Time.current)
  end

  def stamp_open_phases!(generation)
    return unless generation

    now = Time.current
    attrs = {}
    attrs[:prompt_finished_at] = now if generation.prompt_started_at && !generation.prompt_finished_at
    attrs[:image_finished_at] = now if generation.image_started_at && !generation.image_finished_at
    generation.update!(attrs) if attrs.any?
  end
end
