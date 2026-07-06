# frozen_string_literal: true

class ChatLlmSettings
  DEFAULTS = {
    "temperature" => nil,
    "top_p" => nil,
    "max_tokens" => nil,
    "top_k" => nil,
    "repeat_penalty" => nil,
    "min_p" => nil
  }.freeze

  RANGES = {
    "temperature" => 0.0..2.0,
    "top_p" => 0.0..1.0,
    "max_tokens" => 256..16_384,
    "top_k" => 0..200,
    "repeat_penalty" => 0.0..2.0,
    "min_p" => 0.0..1.0
  }.freeze

  FLOAT_KEYS = %w[temperature top_p repeat_penalty min_p].freeze
  INTEGER_KEYS = %w[max_tokens top_k].freeze

  attr_reader :temperature, :top_p, :max_tokens, :top_k, :repeat_penalty, :min_p

  def self.from(hash)
    new(hash)
  end

  def self.normalize(hash)
    from(hash).to_h
  end

  def self.apply!(llm_chat, chat:)
    settings = from(chat.llm_params)
    settings.apply!(llm_chat)
  end

  def initialize(hash = nil)
    source = DEFAULTS.merge(stringify(hash))
    @temperature = parse_float(source["temperature"], "temperature")
    @top_p = parse_float(source["top_p"], "top_p")
    @max_tokens = parse_integer(source["max_tokens"], "max_tokens")
    @top_k = parse_integer(source["top_k"], "top_k")
    @repeat_penalty = parse_float(source["repeat_penalty"], "repeat_penalty")
    @min_p = parse_float(source["min_p"], "min_p")
  end

  def apply!(llm_chat)
    llm_chat.with_temperature(temperature) unless temperature.nil?

    params = to_request_params
    return llm_chat if params.empty?

    existing = llm_chat.instance_variable_get(:@params) || {}
    llm_chat.with_params(**existing.merge(params))
  end

  def to_h
    {
      "temperature" => temperature,
      "top_p" => top_p,
      "max_tokens" => max_tokens,
      "top_k" => top_k,
      "repeat_penalty" => repeat_penalty,
      "min_p" => min_p
    }.compact
  end

  def to_request_params
    params = {}
    params[:top_p] = top_p unless top_p.nil?
    params[:max_tokens] = max_tokens unless max_tokens.nil?
    params[:top_k] = top_k unless top_k.nil?
    params[:repeat_penalty] = repeat_penalty unless repeat_penalty.nil?
    params[:min_p] = min_p unless min_p.nil?
    params
  end

  def form_value(key)
    public_send(key)
  end

  private

  def stringify(hash)
    return {} if hash.blank?

    hash.to_h.stringify_keys.compact_blank
  end

  def parse_float(value, key)
    return nil if value.blank?

    number = Float(value)
    range = RANGES.fetch(key)
    number.clamp(range.begin, range.end)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_integer(value, key)
    return nil if value.blank?

    number = Integer(value)
    range = RANGES.fetch(key)
    number.clamp(range.begin, range.end)
  rescue ArgumentError, TypeError
    nil
  end
end
