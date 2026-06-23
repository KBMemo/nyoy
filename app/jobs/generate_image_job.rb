# frozen_string_literal: true

class GenerateImageJob < ApplicationJob
  queue_as :image_generation

  def perform(image_generation_id)
    generation = ImageGeneration.find(image_generation_id)

    switch_model(generation)
    translate_prompt(generation)
    generate_image(generation)

    generation.update!(status: "completed")
  rescue StandardError => e
    generation&.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def switch_model(generation)
    generation.update!(status: "preparing")

    switch = SdCppSwitchClient.new
    return unless switch.configured?

    switch.switch(generation.sd_model)
  end

  def translate_prompt(generation)
    generation.update!(status: "translating")

    prompt = SdPromptTranslator.new.translate(generation.japanese_prompt)
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
      seed: generation.seed || -1
    )

    generation.image.attach(
      io: StringIO.new(png_data),
      filename: "generation-#{generation.id}.png",
      content_type: "image/png"
    )
  end
end
