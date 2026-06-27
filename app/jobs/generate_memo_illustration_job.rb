# frozen_string_literal: true

class GenerateMemoIllustrationJob < ApplicationJob
  queue_as :image_generation

  def perform(memo_illustration_id)
    illustration = MemoIllustration.find(memo_illustration_id)
    illustration.update!(started_at: Time.current, status: "preparing")

    switch_model(illustration)
    plan_prompts(illustration)
    generate_image(illustration)

    illustration.update!(status: "completed", finished_at: Time.current)
  rescue StandardError => e
    stamp_open_phases!(illustration)
    illustration&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  def switch_model(illustration)
    switch = SdModelSwitcher.new
    switch.switch(illustration.sd_model)
  end

  def plan_prompts(illustration)
    illustration.update!(status: "planning", prompt_started_at: Time.current)

    plan = SdPromptPlanner.new.plan(
      body: illustration.body,
      skill: illustration.prompt_skill,
      record: illustration
    )

    illustration.update!(
      positive_prompt: plan[:positive],
      negative_prompt: plan[:negative],
      width: plan[:width],
      height: plan[:height],
      steps: plan[:steps],
      cfg_scale: plan[:cfg_scale],
      seed: plan[:seed],
      llama_raw_response: plan[:raw_response],
      rag_source_chunk_ids: plan[:source_chunk_ids],
      prompt_finished_at: Time.current
    )
  end

  def generate_image(illustration)
    illustration.update!(status: "generating", image_started_at: Time.current)

    png_data = SdCppClient.new.txt2img(
      prompt: illustration.positive_prompt,
      negative_prompt: NegativePromptResolver.resolve(
        user: illustration.negative_prompt,
        skill: illustration.prompt_skill
      ),
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
    illustration.update!(image_finished_at: Time.current)
  end

  def stamp_open_phases!(illustration)
    return unless illustration

    now = Time.current
    attrs = {}
    attrs[:prompt_finished_at] = now if illustration.prompt_started_at && !illustration.prompt_finished_at
    attrs[:image_finished_at] = now if illustration.image_started_at && !illustration.image_finished_at
    illustration.update!(attrs) if attrs.any?
  end
end
