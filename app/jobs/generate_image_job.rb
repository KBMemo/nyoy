# frozen_string_literal: true

class GenerateImageJob < ApplicationJob
  queue_as :image_generation

  def perform(image_generation_id)
    generation = ImageGeneration.find(image_generation_id)
    generation.update!(started_at: Time.current, status: "preparing")

    prepare_prompt(generation)
    switch_model(generation)
    generate_drafts(generation)

    generation.update!(status: "awaiting_selection")
  rescue StandardError => e
    stamp_open_phases!(generation)
    generation&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  def prepare_prompt(generation)
    if generation.prompt.present? && generation.style_id.present?
      apply_style_from_prompt!(generation)
    elsif generation.prompt.present?
      return
    else
      plan_and_resolve!(generation)
    end
  end

  def plan_and_resolve!(generation)
    generation.update!(status: "translating", prompt_started_at: Time.current)

    plan = StylePlanGenerator.new(flow: :free).call(
      generation.japanese_prompt,
      forced_style_id: generation.style_id.presence
    )

    resolved = SdPromptStyleResolver.new(
      style_id: plan.style_id,
      subject_prompt: plan.subject_prompt,
      negative_extra: plan.negative_extra,
      aspect_ratio: plan.aspect_ratio
    ).call

    persist_resolved!(generation, plan, resolved)
    generation.update!(prompt_finished_at: Time.current)
  end

  def apply_style_from_prompt!(generation)
    generation.update!(status: "translating", prompt_started_at: Time.current)

    resolved = SdPromptStyleResolver.new(
      style_id: generation.style_id,
      subject_prompt: generation.prompt,
      negative_extra: generation.negative_prompt,
      execution_only: true
    ).call

    persist_resolved!(generation, nil, resolved, keep_prompt: true)
    generation.update!(prompt_finished_at: Time.current)
  end

  def persist_resolved!(generation, plan, resolved, keep_prompt: false)
    params = resolved[:resolved_params].merge("switch_key" => resolved[:switch_key])
    attrs = {
      style_id: resolved[:style_id],
      sd_model: resolved[:resolved_model_key],
      negative_prompt: plan&.negative_extra.presence || generation.negative_prompt,
      resolved_negative_prompt: resolved[:resolved_negative_prompt],
      resolved_loras: resolved[:resolved_loras],
      resolved_params: params,
      width: params["width"] || generation.width,
      height: params["height"] || generation.height,
      steps: params["steps"] || generation.steps,
      cfg_scale: params["cfg_scale"] || generation.cfg_scale,
      sampler_name: params["sampler_name"] || generation.sampler_name,
      rag_source_chunk_ids: plan&.source_chunk_ids || generation.rag_source_chunk_ids
    }
    attrs[:prompt] = resolved[:resolved_prompt] unless keep_prompt
    generation.update!(attrs)
  end

  def switch_model(generation)
    switch_key = generation.resolved_params["switch_key"].presence || generation.sd_model
    SdModelSwitcher.new.switch(switch_key)
  end

  def generate_drafts(generation)
    generation.update!(status: "drafting", image_started_at: Time.current)

    params = generation.resolved_params
    png_list = SdCppClient.new.txt2img(
      prompt: generation.prompt,
      negative_prompt: generation.resolved_negative_prompt,
      width: generation.width,
      height: generation.height,
      steps: generation.draft_steps_for_api,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: params["sampler_name"] || generation.sampler_name,
      vae_tiling: params["vae_tiling"],
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
