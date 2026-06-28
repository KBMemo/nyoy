# frozen_string_literal: true

class GenerateMemoIllustrationJob < ApplicationJob
  queue_as :image_generation

  def perform(memo_illustration_id)
    illustration = MemoIllustration.find(memo_illustration_id)
    illustration.update!(started_at: Time.current, status: "preparing")

    resolved = plan_prompts(illustration)
    generate_image(illustration, resolved)

    illustration.update!(status: "completed", finished_at: Time.current)
  rescue StandardError => e
    stamp_open_phases!(illustration)
    illustration&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  def plan_prompts(illustration)
    illustration.update!(status: "planning", prompt_started_at: Time.current)

    plan = StylePlanGenerator.new(flow: :memo).call(
      illustration.body,
      forced_style_id: illustration.style_id.presence
    )

    resolved = SdPromptStyleResolver.new(
      style_id: plan.style_id,
      subject_prompt: plan.subject_prompt,
      negative_extra: plan.negative_extra,
      aspect_ratio: plan.aspect_ratio
    ).call

    params = resolved[:resolved_params]
    illustration.update!(
      style_id: resolved[:style_id],
      sd_model: resolved[:resolved_model_key],
      positive_prompt: resolved[:resolved_prompt],
      negative_prompt: plan.negative_extra,
      resolved_negative_prompt: resolved[:resolved_negative_prompt],
      resolved_loras: resolved[:resolved_loras],
      resolved_params: params,
      width: params["width"] || illustration.width,
      height: params["height"] || illustration.height,
      steps: params["steps"] || illustration.steps,
      cfg_scale: params["cfg_scale"] || illustration.cfg_scale,
      llama_raw_response: plan.raw_response,
      rag_source_chunk_ids: plan.source_chunk_ids,
      prompt_finished_at: Time.current
    )

    resolved
  end

  def generate_image(illustration, resolved)
    illustration.update!(status: "generating", image_started_at: Time.current)

    switch_model(resolved)

    params = illustration.resolved_params
    png_data = SdCppClient.new.txt2img(
      prompt: illustration.positive_prompt,
      negative_prompt: illustration.resolved_negative_prompt,
      width: illustration.width,
      height: illustration.height,
      steps: illustration.steps,
      cfg_scale: illustration.cfg_scale,
      seed: illustration.seed || -1,
      sampler_name: params["sampler_name"],
      lora: illustration.loras_for_api
    )

    illustration.image.attach(
      io: StringIO.new(png_data),
      filename: "memo-illustration-#{illustration.id}.png",
      content_type: "image/png"
    )
    illustration.update!(image_finished_at: Time.current)
  end

  def switch_model(resolved)
    SdModelSwitcher.new.switch(resolved[:switch_key])
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
