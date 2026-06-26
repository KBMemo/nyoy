# frozen_string_literal: true

# Merges execution-time fixed negatives (skill + preset) with supplemental tags
# stored on the record (form input, RAG PromptSpec, memo planner output).
class NegativePromptResolver
  def self.resolve(supplemental: nil, user: nil, preset: nil, skill: nil)
    new(supplemental: supplemental || user, preset: preset, skill: skill).resolve
  end

  def self.base(preset: nil, skill: nil)
    new(preset: preset, skill: skill).base
  end

  def self.for_generation(generation)
    resolve(
      supplemental: generation.negative_prompt,
      preset: generation.generation_preset,
      skill: generation.prompt_skill
    )
  end

  def initialize(supplemental: nil, preset: nil, skill: nil)
    @supplemental = supplemental
    @preset = preset
    @skill = skill
  end

  def resolve
    fixed = base
    extra = @supplemental.to_s.strip

    return fixed if extra.blank?
    return extra if fixed.blank?

    merge_tags(fixed, extra)
  end

  def base
    merge_tags(@skill&.default_negative_prompt, @preset&.default_negative_prompt)
  end

  private

  def merge_tags(*parts)
    parts
      .flat_map { |part| split_tags(part) }
      .uniq
      .join(", ")
  end

  def split_tags(text)
    text.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
