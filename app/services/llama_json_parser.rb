# frozen_string_literal: true

class LlamaJsonParser
  class Error < StandardError; end

  def self.normalize(text)
    new(text).normalize
  end

  def self.parse(text)
    new(text).parse
  end

  def initialize(text)
    @text = text.to_s
  end

  def normalize
    stripped = strip_markdown_fences(@text.strip)
    return stripped if stripped.start_with?("{")

    extract_json_object(stripped)
  end

  def parse
    json_text = normalize
    raise Error, "no JSON object found in llama response" if json_text.blank?

    JSON.parse(json_text)
  rescue JSON::ParserError => e
    raise Error, "invalid JSON from llama: #{e.message}"
  end

  private

  def strip_markdown_fences(text)
    return text unless text.include?("```")

    text = text.sub(/\A.*?```(?:json)?\s*/im, "")
    text.sub(/\s*```.*\z/m, "").strip
  end

  def extract_json_object(text)
    start = text.index("{")
    return nil unless start

    depth = 0
    text[start..].each_char.with_index do |char, index|
      depth += 1 if char == "{"
      depth -= 1 if char == "}"

      return text[start, index + 1] if depth.zero?
    end

    text[start..]
  end
end
