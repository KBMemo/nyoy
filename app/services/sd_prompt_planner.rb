# frozen_string_literal: true

class SdPromptPlanner
  class Error < StandardError; end

  DEFAULTS = {
    width: 512,
    height: 512,
    steps: 20,
    cfg_scale: 7.0,
    seed: -1
  }.freeze

  MAX_TOKENS = 4096

  def initialize(client: LlamaCppClient.new)
    @client = client
  end

  def plan(body:, skill:)
    response = @client.chat(
      messages: [
        { role: "system", content: skill.body },
        { role: "user", content: body }
      ],
      temperature: 0.2,
      max_tokens: MAX_TOKENS
    )

    content = LlamaCppClient.message_text(response)
    raise Error, "empty response from llama" if content.blank?

    parse_plan(content)
  end

  private

  def parse_plan(content)
    json = extract_json(content)
    positive = json["positive"].to_s.strip
    negative = json["negative"].to_s.strip

    raise Error, "positive prompt required" if positive.blank?

    {
      positive: positive,
      negative: negative,
      width: integer_param(json, "width", DEFAULTS[:width]),
      height: integer_param(json, "height", DEFAULTS[:height]),
      steps: integer_param(json, "steps", DEFAULTS[:steps]),
      cfg_scale: float_param(json, "cfg_scale", DEFAULTS[:cfg_scale]),
      seed: integer_param(json, "seed", DEFAULTS[:seed]),
      raw_response: content
    }
  end

  def extract_json(content)
    json_text = normalize_json_text(content)
    raise Error, "no JSON object found in llama response" if json_text.blank?

    JSON.parse(json_text)
  rescue JSON::ParserError
    salvaged = salvage_json(json_text)
    raise Error, "invalid JSON from llama" if salvaged.blank? || salvaged["positive"].blank?

    salvaged
  end

  def normalize_json_text(content)
    text = content.to_s.strip

    if text.include?("```")
      text = text.sub(/\A.*?```(?:json)?\s*/im, "")
      text = text.sub(/\s*```.*\z/m, "")
    end

    text = text.strip
    text.start_with?("{") ? text : text[/(\{.*)/ms]
  end

  def salvage_json(text)
    result = {}

    %w[positive negative].each do |key|
      value = extract_string_field(text, key)
      result[key] = value if value.present?
    end

    {
      "width" => "integer",
      "height" => "integer",
      "steps" => "integer",
      "seed" => "integer"
    }.each do |key, type|
      next unless (match = text.match(/"#{key}"\s*:\s*(-?\d+(?:\.\d+)?)/))

      result[key] = type == "integer" ? match[1].to_i : match[1]
    end

    if (match = text.match(/"cfg_scale"\s*:\s*(-?\d+(?:\.\d+)?)/))
      result["cfg_scale"] = match[1].to_f
    end

    result.presence
  end

  def extract_string_field(text, key)
    patterns = [
      /"#{key}"\s*:\s*"((?:\\.|[^"\\])*)"/m,
      /"#{key}"\s*:\s*"((?:\\.|[^"\\])*)/m
    ]

    patterns.each do |pattern|
      next unless (match = text.match(pattern))

      return unescape_json_string(match[1])
    end

    nil
  end

  def unescape_json_string(value)
    JSON.parse(%("#{value}"))
  rescue JSON::ParserError
    value.gsub('\\"', '"').gsub("\\\\", "\\")
  end

  def integer_param(json, key, fallback)
    value = json.key?(key) ? json[key] : fallback
    value.to_i
  end

  def float_param(json, key, fallback)
    value = json.key?(key) ? json[key] : fallback
    value.to_f
  end
end
