# frozen_string_literal: true

class NegativePromptResolver
  def self.resolve(user: nil, preset: nil, skill: nil)
    new(user: user, preset: preset, skill: skill).resolve
  end

  def self.for_generation(generation)
    resolve(
      user: generation.negative_prompt,
      preset: generation.generation_preset,
      skill: generation.prompt_skill
    )
  end

  def initialize(user: nil, preset: nil, skill: nil)
    @user = user
    @preset = preset
    @skill = skill
  end

  def resolve
    base = merge_tags(@skill&.default_negative_prompt, @preset&.default_negative_prompt)
    user = @user.to_s.strip

    return base if user.blank?
    return user if base.blank?

    merge_tags(base, user)
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
