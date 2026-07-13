# frozen_string_literal: true

# Shared sampling / generation request parameters for llama-server OpenAI-compatible chat.
class LlmSamplingParams
  KEYS = %w[
    temperature
    top_p
    top_k
    min_p
    presence_penalty
    frequency_penalty
    repeat_penalty
    max_tokens
  ].freeze

  FLOAT_KEYS = %w[
    temperature
    top_p
    min_p
    presence_penalty
    frequency_penalty
    repeat_penalty
  ].freeze

  # HTML number inputs: allow fine values (e.g. repeat_penalty 1.08). Avoid step=0.05 validation traps.
  FLOAT_INPUT_STEP = "any"

  INTEGER_KEYS = %w[top_k max_tokens].freeze

  RANGES = {
    "temperature" => 0.0..2.0,
    "top_p" => 0.0..1.0,
    "top_k" => 0..200,
    "min_p" => 0.0..1.0,
    "presence_penalty" => -2.0..2.0,
    "frequency_penalty" => -2.0..2.0,
    "repeat_penalty" => 0.0..2.0,
    "max_tokens" => 64..16_384
  }.freeze

  # llama-server /props default_generation_settings.params → our keys
  PROPS_KEY_MAP = {
    "temperature" => "temperature",
    "top_p" => "top_p",
    "top_k" => "top_k",
    "min_p" => "min_p",
    "presence_penalty" => "presence_penalty",
    "frequency_penalty" => "frequency_penalty",
    "repeat_penalty" => "repeat_penalty",
    "penalty_repeat" => "repeat_penalty",
    "n_predict" => "max_tokens",
    "max_tokens" => "max_tokens"
  }.freeze

  attr_reader(*KEYS.map(&:to_sym))

  def self.from(hash)
    new(hash)
  end

  def self.normalize(hash)
    from(hash).to_h
  end

  def self.from_props(props)
    params =
      if props.is_a?(Hash)
        props.dig("default_generation_settings", "params") || props["params"]
      end
    mapped = {}
    if params.is_a?(Hash)
      params.each do |key, value|
        ours = PROPS_KEY_MAP[key.to_s]
        next if ours.blank?

        mapped[ours] = value
      end
    end
    from(mapped)
  end

  def self.merge(base, overlay)
    from(normalize(base).merge(normalize(overlay).compact))
  end

  def initialize(hash = nil)
    source = stringify(hash)
    KEYS.each do |key|
      value =
        if FLOAT_KEYS.include?(key)
          parse_float(source[key], key)
        else
          parse_integer(source[key], key)
        end
      instance_variable_set(:"@#{key}", value)
    end
  end

  def to_h
    KEYS.index_with { |key| public_send(key) }
  end

  def to_h_compact
    to_h.compact
  end

  def to_request_params
    params = {}
    params[:top_p] = top_p unless top_p.nil?
    params[:top_k] = top_k unless top_k.nil?
    params[:min_p] = min_p unless min_p.nil?
    params[:presence_penalty] = presence_penalty unless presence_penalty.nil?
    params[:frequency_penalty] = frequency_penalty unless frequency_penalty.nil?
    params[:repeat_penalty] = repeat_penalty unless repeat_penalty.nil?
    params
  end

  def resolved_temperature(default:)
    temperature.nil? ? default : temperature
  end

  def resolved_max_tokens(default:)
    max_tokens.nil? ? default : max_tokens
  end

  private

  def stringify(hash)
    return {} if hash.blank?

    hash.to_h.stringify_keys
  end

  def parse_float(value, key)
    return nil if value.nil? || value.to_s.strip.blank?

    number = Float(value)
    range = RANGES.fetch(key)
    number.clamp(range.begin, range.end)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_integer(value, key)
    return nil if value.nil? || value.to_s.strip.blank?

    number = Integer(value)
    range = RANGES.fetch(key)
    number.clamp(range.begin, range.end)
  rescue ArgumentError, TypeError
    nil
  end
end
