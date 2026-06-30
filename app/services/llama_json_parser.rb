# frozen_string_literal: true

class LlamaJsonParser
  class Error < StandardError; end

  def self.normalize(text)
    new(text).normalize
  end

  def self.parse(text)
    new(text).parse
  end

  def self.repair_truncated(text)
    new(text).repair_truncated
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

    parse_json(json_text)
  end

  def repair_truncated
    json_text = normalize.to_s.strip
    raise Error, "no JSON object found in llama response" if json_text.blank?

    parse_json(json_text)
  rescue Error
    repaired = close_truncated_object(json_text)
    parse_json(repaired)
  end

  private

  def parse_json(json_text)
    JSON.parse(json_text)
  rescue JSON::ParserError => e
    raise Error, "invalid JSON from llama: #{e.message}"
  end

  def close_truncated_object(text)
    repaired = text.strip
    repaired += '"' if quote_count_odd?(repaired)

    unless repaired.end_with?("}")
      repaired += trailing_fields_for(repaired)
      repaired += "}" unless repaired.end_with?("}")
    end

    repaired
  end

  def trailing_fields_for(text)
    fields = []
    fields << '"negative_extra": ""' unless text.match?(/"negative_extra"\s*:/)
    fields << '"aspect_ratio": "square"' unless text.match?(/"aspect_ratio"\s*:/)

    return "" if fields.empty?

    separator = text.end_with?('"') ? ", " : ', "'
    separator + fields.join(", ")
  end

  def quote_count_odd?(text)
    text.count('"').odd?
  end

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
