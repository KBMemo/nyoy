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

  def initialize(client: LlamaCppClient.new)
    @client = client
  end

  def plan(body:, skill:)
    response = @client.chat(
      messages: [
        { role: "system", content: skill.body },
        { role: "user", content: body }
      ],
      temperature: 0.3,
      max_tokens: 1024
    )

    content = response.dig("choices", 0, "message", "content").to_s
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
    text = content.to_s.strip

    if text.include?("```")
      text = text.sub(/\A.*?```(?:json)?\s*/im, "")
      text = text.sub(/\s*```.*\z/m, "")
    end

    text = text.strip
    json_text = text.start_with?("{") ? text : text[/(\{.*\})/ms]

    raise Error, "no JSON object found in llama response" if json_text.blank?

    JSON.parse(json_text)
  rescue JSON::ParserError => e
    raise Error, "invalid JSON from llama: #{e.message}"
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
