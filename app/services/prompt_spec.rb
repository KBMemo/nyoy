# frozen_string_literal: true

class PromptSpec
  class ValidationError < StandardError; end

  attr_reader :positive_prompt, :negative_prompt, :model_family, :width, :height, :steps,
    :cfg_scale, :sampler, :seed, :loras, :notes_ja, :source_chunk_ids, :raw_response

  def initialize(attrs = {})
    @positive_prompt = attrs[:positive_prompt].to_s.strip
    @negative_prompt = attrs[:negative_prompt].to_s.strip
    @model_family = attrs[:model_family].to_s.strip.presence
    @width = attrs[:width]
    @height = attrs[:height]
    @steps = attrs[:steps]
    @cfg_scale = attrs[:cfg_scale]
    @sampler = attrs[:sampler].to_s.strip.presence
    @seed = attrs[:seed]
    @loras = Array(attrs[:loras]).map { |entry| normalize_lora(entry) }.compact
    @notes_ja = attrs[:notes_ja].to_s.strip.presence
    @source_chunk_ids = Array(attrs[:source_chunk_ids]).map(&:to_i).uniq
    @raw_response = attrs[:raw_response]
  end

  def self.from_json(json, source_chunk_ids: [], raw_response: nil)
    new(
      positive_prompt: json["positive_prompt"] || json["positive"],
      negative_prompt: json["negative_prompt"] || json["negative"],
      model_family: json["model_family"],
      width: json["width"],
      height: json["height"],
      steps: json["steps"],
      cfg_scale: json["cfg_scale"],
      sampler: json["sampler"] || json["sampler_name"],
      seed: json["seed"],
      loras: json["loras"],
      notes_ja: json["notes_ja"],
      source_chunk_ids: source_chunk_ids.presence || json["source_chunk_ids"],
      raw_response: raw_response
    )
  end

  def validate!(allowed_loras:, allowed_samplers:, allowed_models:)
    raise ValidationError, "positive_prompt required" if positive_prompt.blank?

    loras.each do |entry|
      name = entry["name"]
      next if allowed_loras.include?(name)

      raise ValidationError, "unknown LoRA: #{name}"
    end

    if sampler.present? && !allowed_samplers.include?(sampler)
      raise ValidationError, "unknown sampler: #{sampler}"
    end

    if model_family.present? && allowed_models.present? && !allowed_models.include?(model_family)
      raise ValidationError, "unknown model: #{model_family}"
    end

    self
  end

  def to_h
    {
      "positive_prompt" => positive_prompt,
      "negative_prompt" => negative_prompt,
      "model_family" => model_family,
      "width" => width,
      "height" => height,
      "steps" => steps,
      "cfg_scale" => cfg_scale,
      "sampler" => sampler,
      "seed" => seed,
      "loras" => loras,
      "notes_ja" => notes_ja,
      "source_chunk_ids" => source_chunk_ids
    }.compact
  end

  def apply_to_generation!(generation)
    attrs = {
      prompt: positive_prompt,
      prompt_spec: to_h,
      rag_source_chunk_ids: source_chunk_ids
    }
    attrs[:negative_prompt] = negative_prompt if negative_prompt.present?
    attrs[:width] = width.to_i if width.present?
    attrs[:height] = height.to_i if height.present?
    attrs[:steps] = steps.to_i if steps.present?
    attrs[:cfg_scale] = cfg_scale.to_f if cfg_scale.present?
    attrs[:seed] = seed.to_i if seed.present?
    attrs[:sampler_name] = sampler if sampler.present?
    attrs[:sd_model] = model_family if model_family.present?

    if loras.any?
      attrs[:loras] = JSON.generate(
        loras.map do |entry|
          {
            "name" => entry["name"],
            "path" => entry["path"],
            "multiplier" => entry["weight"] || entry["multiplier"] || 1.0
          }.compact
        end
      )
    end

    generation.update!(attrs)
  end

  private

  def normalize_lora(entry)
    return nil unless entry.is_a?(Hash)

    name = entry["name"].to_s.strip
    return nil if name.blank?

    {
      "name" => name,
      "path" => entry["path"].presence,
      "weight" => (entry["weight"] || entry["multiplier"] || 1.0).to_f
    }
  end
end
