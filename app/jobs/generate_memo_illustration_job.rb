# frozen_string_literal: true

class GenerateMemoIllustrationJob < ApplicationJob
  queue_as :image_generation

  def perform(memo_illustration_id)
    illustration = MemoIllustration.find(memo_illustration_id)

    switch_model(illustration)
    plan_prompts(illustration)
    generate_image(illustration)

    illustration.update!(status: "completed")
  rescue StandardError => e
    illustration&.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def switch_model(illustration)
    illustration.update!(status: "preparing")

    switch = SdModelSwitcher.new
    switch.switch(illustration.sd_model)
  end

  def plan_prompts(illustration)
    illustration.update!(status: "planning")

    plan = SdPromptPlanner.new.plan(
      body: illustration.body,
      skill: illustration.prompt_skill
    )

    illustration.update!(
      positive_prompt: plan[:positive],
      negative_prompt: plan[:negative],
      width: plan[:width],
      height: plan[:height],
      steps: plan[:steps],
      cfg_scale: plan[:cfg_scale],
      seed: plan[:seed],
      llama_raw_response: plan[:raw_response]
    )
  end

  def generate_image(illustration)
    illustration.update!(status: "generating")

    png_data = SdCppClient.new.txt2img(
      prompt: illustration.positive_prompt,
      negative_prompt: illustration.negative_prompt.to_s,
      width: illustration.width,
      height: illustration.height,
      steps: illustration.steps,
      cfg_scale: illustration.cfg_scale,
      seed: illustration.seed || -1
    )

    illustration.image.attach(
      io: StringIO.new(png_data),
      filename: "memo-illustration-#{illustration.id}.png",
      content_type: "image/png"
    )
  end
end
