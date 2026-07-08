# frozen_string_literal: true

# Resolves a minimal LLM plan (style_id + subject_prompt + negative prompt +
# aspect_ratio) into a concrete sd.cpp payload using DB-backed PromptStyle data.
# The LLM never picks numbers, model paths, or LoRA paths — they come from here.
class SdPromptStyleResolver
  class Error < StandardError; end

  def initialize(style_id:, subject_prompt:, negative_extra: nil, aspect_ratio: nil,
                 model_key: nil, overrides: {}, execution_only: false)
    @style_id = style_id.to_s
    @subject_prompt = subject_prompt.to_s.strip
    @negative_extra = negative_extra.to_s.strip
    @aspect_ratio = aspect_ratio
    @model_key = model_key.presence
    @overrides = (overrides || {}).transform_keys(&:to_s)
    @execution_only = execution_only
  end

  def call
    style = find_style
    style_model = pick_style_model(style)
    model = style_model.sd_model_profile

    params = model.resolved_default_params
      .deep_merge(style_model.param_overrides.to_h)
      .deep_merge(style.generation_defaults.to_h)
      .deep_merge(aspect_params(style))
      .deep_merge(safe_overrides(style))

    prompt = @execution_only ? @subject_prompt : build_prompt(style)
    negative = NegativePromptResolver.merge(style.negative_prompt, @negative_extra)
    loras = resolve_loras(style)

    {
      style_id: style.style_id,
      switch_key: model.switch_key,
      base_url: model.base_url,
      resolved_model_key: model.key,
      resolved_prompt: prompt,
      resolved_negative_prompt: negative,
      resolved_loras: loras,
      resolved_params: params,
      payload: params.merge(
        "prompt" => prompt,
        "negative_prompt" => negative,
        "lora" => loras
      )
    }
  end

  private

  def find_style
    raise Error, "subject_prompt required" if @subject_prompt.blank? && !@execution_only

    style = PromptStyle.includes(prompt_style_models: :sd_model_profile,
                                 prompt_style_loras: :lora_profile)
                       .find_by(style_id: @style_id, enabled: true)
    raise Error, "unknown style_id: #{@style_id}" if style.nil?

    style
  end

  def pick_style_model(style)
    style_model = style.style_model_for(@model_key) || style.default_style_model
    raise Error, "style #{@style_id} has no model" if style_model.nil?

    style_model
  end

  def aspect_params(style)
    dims = style.aspect_dimensions(@aspect_ratio)
    dims.is_a?(Hash) ? dims.slice("width", "height") : {}
  end

  def build_prompt(style)
    [
      style.prompt_prefix,
      @subject_prompt.presence,
      trigger_words(style).presence,
      style.prompt_suffix
    ].compact_blank.join(", ")
  end

  def trigger_words(style)
    style.prompt_style_loras
      .select(&:inject_trigger_words?)
      .flat_map { |link| link.lora_profile.trigger_words_list }
      .uniq
      .join(", ")
  end

  def resolve_loras(style)
    style.prompt_style_loras
      .sort_by(&:sort_order)
      .filter_map do |link|
        next unless link.lora_profile.enabled?

        { "path" => link.lora_profile.path, "multiplier" => link.multiplier.to_f }
      end
  end

  def safe_overrides(style)
    allowed = style.allowed_overrides.to_h
    result = {}

    @overrides.each do |key, value|
      rule = allowed[key]
      next if rule.nil?

      resolved =
        case rule
        when Array then rule.include?(value) ? value : nil
        when Hash then clamp_number(value, rule)
        end
      result[key] = resolved unless resolved.nil?
    end

    result
  end

  def clamp_number(value, rule)
    number = Float(value)
    min = rule["min"] || rule[:min]
    max = rule["max"] || rule[:max]
    number = [number, Float(min)].max if min
    number = [number, Float(max)].min if max
    number
  rescue ArgumentError, TypeError
    nil
  end
end
