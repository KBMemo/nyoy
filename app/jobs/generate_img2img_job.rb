# frozen_string_literal: true

class GenerateImg2imgJob < ApplicationJob
  queue_as :image_generation

  def perform(img2img_generation_id)
    generation = Img2imgGeneration.find(img2img_generation_id)
    generation.update!(started_at: Time.current, status: "preparing")

    prepare_prompt(generation)
    switch_model(generation)
    generate_image(generation)

    generation.update!(status: "completed", finished_at: Time.current)
  rescue StandardError => e
    stamp_open_phases!(generation)
    generation&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  def prepare_prompt(generation)
    return if generation.prompt.present?

    plan_and_resolve!(generation)
  end

  def plan_and_resolve!(generation)
    generation.update!(status: "translating", prompt_started_at: Time.current)

    plan = StylePlanGenerator.new(flow: :free).call(
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
      steps: params["steps"] || generation.steps,
      cfg_scale: params["cfg_scale"] || generation.cfg_scale,
      sampler_name: params["sampler_name"] || generation.sampler_name,
      rag_source_chunk_ids: plan&.source_chunk_ids || generation.rag_source_chunk_ids
    }

    unless generation.use_source_dimensions?
      attrs[:width] = params["width"] || generation.width
      attrs[:height] = params["height"] || generation.height
    end

    attrs[:prompt] = resolved[:resolved_prompt] unless keep_prompt
    generation.update!(attrs)
  end

  def switch_model(generation)
    switch_key = generation.resolved_params["switch_key"].presence || generation.sd_model
    SdModelSwitcher.new.switch(switch_key)
  end

  def generate_image(generation)
    generation.update!(status: "generating", image_started_at: Time.current)

    init_image = generation.source_image.download
    width, height = output_dimensions(generation, init_image)
    generation.update!(width: width, height: height)

    params = generation.resolved_params
    png_data = SdCppClient.new.img2img(
      prompt: generation.prompt,
      negative_prompt: generation.resolved_negative_prompt,
      init_image: init_image,
      width: width,
      height: height,
      steps: generation.steps,
      cfg_scale: generation.cfg_scale,
      seed: generation.seed || -1,
      sampler_name: params["sampler_name"] || generation.sampler_name,
      vae_tiling: params["vae_tiling"].nil? ? generation.vae_tiling : params["vae_tiling"],
      denoising_strength: generation.denoising_strength,
      lora: generation.loras_for_api
    )

    generation.image.attach(
      io: StringIO.new(png_data),
      filename: "img2img-#{generation.id}.png",
      content_type: "image/png"
    )
    generation.update!(image_finished_at: Time.current)
  end

  def output_dimensions(generation, init_image)
    if generation.use_source_dimensions?
      png_dimensions(init_image)
    else
      [generation.width, generation.height]
    end
  end

  def png_dimensions(png_data)
    image = Vips::Image.new_from_buffer(png_data, "")
    [image.width, image.height]
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
