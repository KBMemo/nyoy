# frozen_string_literal: true

class GenerateImageJob < ApplicationJob
  queue_as :image_generation

  def perform(image_generation_id)
    generation = ImageGeneration.find(image_generation_id)
    generation.update!(started_at: Time.current, status: "preparing")

    switch_model(generation)
    translate_prompt(generation)
    generate_image(generation)

    generation.update!(status: "completed", finished_at: Time.current)
  rescue StandardError => e
    generation&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  def switch_model(generation)
    switch = SdModelSwitcher.new
    switch.switch(generation.sd_model, lora: generation.switch_lora_name)
  end

  def translate_prompt(generation)
    generation.update!(status: "translating")

    prompt = SdPromptTranslator.new.translate(
      generation.japanese_prompt,
      skill: generation.prompt_skill
    )
    generation.update!(prompt: prompt)
  end

  def generate_image(generation)
    generation.update!(status: "generating")

    png_data = SdCppClient.new.txt2img(
      prompt: generation.prompt,
      negative_prompt: generation.negative_prompt.to_s,
      width: generation.width,
      height: generation.height,
      steps: generation.steps,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: generation.sampler_name,
      vae_tiling: generation.vae_tiling,
      lora: generation.loras_for_api
    )

    generation.image.attach(
      io: StringIO.new(png_data),
      filename: "generation-#{generation.id}.png",
      content_type: "image/png"
    )
  end
end
