# frozen_string_literal: true

# Tag-aware merge of comma-separated negative prompt parts.
class NegativePromptResolver
  def self.merge(*parts)
    new.send(:merge_tags, *parts)
  end

  def self.for_generation(generation)
    generation.negative_prompt.to_s.strip
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
