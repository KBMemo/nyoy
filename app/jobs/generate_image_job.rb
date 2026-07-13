# frozen_string_literal: true

class GenerateImageJob < ApplicationJob
  queue_as :image_generation

  def perform(image_generation_id)
    generation = ImageGeneration.find(image_generation_id)
    generation.update!(started_at: Time.current, status: "preparing")

    if generation.direct_flow?
      generate_direct(generation)
    else
      generate_draft_flow(generation)
    end
  rescue StandardError => e
    stamp_open_phases!(generation)
    generation&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  def generate_draft_flow(generation)
    prepare_prompt(generation)
    switch_model(generation)
    generate_drafts(generation)

    generation.update!(status: "awaiting_selection")
  end

  def generate_direct(generation)
    prepare_direct_prompt(generation)
    persist_direct_resolved!(generation)
    switch_model(generation)
    generate_direct_image(generation)

    generation.update!(status: "completed", image_finished_at: Time.current, finished_at: Time.current)
  end

  def prepare_direct_prompt(generation)
    if generation.prompt.present?
      generation.update!(
        resolved_negative_prompt: generation.negative_prompt.presence || generation.resolved_negative_prompt
      )
      return
    end

    generation.update!(status: "generating_prompt", prompt_started_at: Time.current)

    profile = generation.sd_model_profile
    raise "sd_model_profile required" if profile.blank?

    template = generation.sd_prompt_template.presence ||
      SdPromptTemplateResolver.for(sd_model_profile: profile)

    result = DirectPromptGenerator.new(connection_key: generation.style_plan_connection_key).generate(
      generation.japanese_prompt,
      sd_model_profile: profile,
      sd_prompt_template: template
    )

    generation.update!(
      prompt: result[:prompt],
      negative_prompt: generation.negative_prompt.presence || result[:negative_prompt],
      resolved_negative_prompt: result[:negative_prompt],
      sd_prompt_template_id: result[:sd_prompt_template_id],
      prompt_finished_at: Time.current
    )
  end

  def persist_direct_resolved!(generation)
    profile = generation.sd_model_profile
    raise "sd_model_profile required" if profile.blank?

    params = profile.resolved_default_params.merge(
      "width" => generation.width,
      "height" => generation.height,
      "steps" => generation.steps,
      "cfg_scale" => generation.cfg_scale,
      "sampler_name" => generation.sampler_name,
      "vae_tiling" => generation.vae_tiling,
      "switch_key" => profile.switch_key
    )

    generation.update!(
      sd_model: profile.key,
      resolved_params: params,
      resolved_loras: [],
      resolved_negative_prompt: generation.resolved_negative_prompt,
      width: params["width"],
      height: params["height"],
      steps: params["steps"],
      cfg_scale: params["cfg_scale"],
      sampler_name: params["sampler_name"] || generation.sampler_name
    )
  end

  def generate_direct_image(generation)
    generation.update!(status: "refining", image_started_at: Time.current)

    params = generation.resolved_params
    result = SdCppClient.new.txt2img_all(
      prompt: generation.prompt,
      negative_prompt: generation.resolved_negative_prompt,
      width: generation.width,
      height: generation.height,
      steps: generation.steps,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: params["sampler_name"] || generation.sampler_name,
      vae_tiling: params["vae_tiling"].nil? ? generation.vae_tiling : params["vae_tiling"],
      lora: generation.loras_for_api
    )
    generation.record_actual_seed!(result.seed)

    generation.refined_images.attach(
      io: StringIO.new(result.images.first),
      filename: "direct-#{generation.id}-1.png",
      content_type: "image/png",
      metadata: { direct: true, sequence: 1 }
    )
  end

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

    plan = StylePlanGenerator.new(flow: :free, connection_key: generation.style_plan_connection_key).call(
      generation.japanese_prompt,
      forced_style_id: generation.style_id.presence
    )

    negative_for_resolve = generation.negative_prompt.presence || plan.negative_extra
    resolved = SdPromptStyleResolver.new(
      style_id: plan.style_id,
      subject_prompt: plan.subject_prompt,
      negative_extra: negative_for_resolve,
      aspect_ratio: resolve_aspect_ratio(generation, plan)
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
      aspect_ratio: generation.aspect_ratio.presence,
      execution_only: true
    ).call

    persist_resolved!(generation, nil, resolved, keep_prompt: true)
    generation.update!(prompt_finished_at: Time.current)
  end

  def resolve_aspect_ratio(generation, plan)
    generation.aspect_ratio.presence || plan&.aspect_ratio
  end

  def persist_resolved!(generation, plan, resolved, keep_prompt: false)
    params = resolved[:resolved_params].merge("switch_key" => resolved[:switch_key])
    attrs = {
      style_id: resolved[:style_id],
      aspect_ratio: generation.aspect_ratio.presence || plan&.aspect_ratio,
      sd_model: resolved[:resolved_model_key],
      negative_prompt: generation.negative_prompt.presence || plan&.negative_extra,
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
    switch_key = generation.resolved_params.to_h["switch_key"].presence ||
      generation.sd_model_profile&.switch_key.presence ||
      generation.sd_model.presence
    SdModelSwitcher.new.switch(switch_key)
  end

  def generate_drafts(generation)
    generation.update!(status: "drafting", image_started_at: Time.current)

    params = generation.resolved_params
    result = SdCppClient.new.txt2img_all(
      prompt: generation.prompt,
      negative_prompt: generation.resolved_negative_prompt,
      width: generation.draft_width,
      height: generation.draft_height,
      steps: generation.draft_steps_for_api,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: params["sampler_name"] || generation.sampler_name,
      vae_tiling: params["vae_tiling"],
      lora: generation.loras_for_api,
      batch_size: generation.draft_batch_size
    )
    generation.record_actual_seed!(result.seed)

    generation.drafts.purge
    result.images.each_with_index do |png_data, index|
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