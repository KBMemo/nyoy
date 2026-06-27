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

  def initialize(client: LlamaCppClient.new, retriever: PromptKnowledgeRetriever.new, allowed_lists: nil)
    @client = client
    @retriever = retriever
    @allowed_lists = allowed_lists
  end

  def plan(body:, skill:, record: nil)
    rag = build_rag(body, record)
    user_content = build_user_prompt(body, skill, record, rag)

    response = @client.chat(
      messages: [
        { role: "system", content: skill.body },
        { role: "user", content: user_content }
      ],
      temperature: 0.2,
      max_tokens: MAX_TOKENS,
      response_format: response_format
    )

    content = response_text(response)
    raise Error, "empty response from llama" if content.blank?

    parse_plan(content).merge(source_chunk_ids: rag&.dig(:chunk_ids) || [])
  end

  private

  def build_rag(body, record)
    return nil if record.blank?

    PromptRagContext.new(
      record: record,
      retriever: @retriever,
      allowed_lists: @allowed_lists || PromptAllowedLists.new(record: record)
    ).call(body)
  end

  def build_user_prompt(body, skill, record, rag)
    return body if rag.blank?

    <<~PROMPT
      Japanese memo:
      #{body}

      Retrieved knowledge chunks:
      #{rag[:chunk_section]}

      Prompt presets:
      #{rag[:preset_section]}

      LoRA dictionary:
      #{rag[:lora_section]}

      SD model: #{record.sd_model}

      Fixed negative tags are applied automatically at image generation from skill settings.
      Return JSON with keys:
      positive, negative (supplemental tags only), width, height, steps, cfg_scale, seed
    PROMPT
  end

  def response_format
    return unless Rails.application.config.x.nyoy.llama_json_schema

    MemoPromptPlanJsonSchema.build
  end

  def response_text(response)
    sources = LlamaCppClient.message_sources(response)
    sources.find { |text| text.include?("{") } ||
      sources.first ||
      LlamaCppClient.message_text(response)
  end

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
    json_text = LlamaJsonParser.normalize(content)
    raise Error, "no JSON object found in llama response" if json_text.blank?

    JSON.parse(json_text)
  rescue JSON::ParserError
    salvaged = salvage_json(json_text)
    raise Error, "invalid JSON from llama" if salvaged.blank? || salvaged["positive"].blank?

    salvaged
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
