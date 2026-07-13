# frozen_string_literal: true

# Per-LLM-connection settings for style plan / direct prompt conversion.
# Stored under ServiceConnection.settings["prompt_conversion"].
class PromptConversionSettings
  SETTINGS_KEY = "prompt_conversion"
  JSON_SCHEMA_MODES = %w[auto on off].freeze
  ENABLE_THINKING_VALUES = %w[false true unset].freeze

  DEFAULT_TEMPERATURE = 0.2

  DEFAULTS = {
    "json_schema" => "auto",
    # Prompt conversion does not need chain-of-thought; default off to avoid JSON breakage.
    "enable_thinking" => "false"
  }.freeze

  attr_reader :json_schema, :enable_thinking, :sampling

  delegate(*LlmSamplingParams::KEYS.map(&:to_sym), to: :sampling)
  delegate :to_request_params, :resolved_temperature, :resolved_max_tokens, to: :sampling

  def self.from(settings)
    new(extract(settings))
  end

  def self.normalize(attrs)
    new(attrs).to_settings_h
  end

  def self.merge_into(settings, attrs)
    base = (settings || {}).deep_stringify_keys
    base.merge(SETTINGS_KEY => normalize(attrs))
  end

  def self.extract(settings)
    hash = stringify(settings)
    nested = hash[SETTINGS_KEY]
    return stringify(nested) if nested.is_a?(Hash)

    hash.slice(*(DEFAULTS.keys + LlmSamplingParams::KEYS))
  end

  def self.stringify(hash)
    return {} if hash.blank?

    hash.to_h.stringify_keys
  end

  def initialize(source = nil)
    hash = self.class.stringify(source)
    @json_schema = normalize_json_schema(hash.fetch("json_schema", DEFAULTS["json_schema"]))
    @enable_thinking = normalize_enable_thinking(
      hash.key?("enable_thinking") ? hash["enable_thinking"] : DEFAULTS["enable_thinking"]
    )
    @sampling = LlmSamplingParams.from(hash.slice(*LlmSamplingParams::KEYS))
  end

  def json_schema_mode
    json_schema
  end

  def resolved_temperature(default: DEFAULT_TEMPERATURE)
    sampling.resolved_temperature(default: default)
  end

  # nil => omit chat_template_kwargs; true/false => send as boolean
  def enable_thinking_flag
    case enable_thinking
    when "true" then true
    when "false" then false
    end
  end

  def chat_template_kwargs
    flag = enable_thinking_flag
    return nil if flag.nil?

    { "enable_thinking" => flag }
  end

  def to_settings_h
    {
      "json_schema" => json_schema,
      "enable_thinking" => enable_thinking
    }.merge(sampling.to_h)
  end

  alias to_h to_settings_h

  private

  def normalize_json_schema(value)
    mode = value.to_s.strip
    return mode if JSON_SCHEMA_MODES.include?(mode)

    DEFAULTS.fetch("json_schema")
  end

  def normalize_enable_thinking(value)
    case value
    when true, "true", "1", 1 then "true"
    when false, "false", "0", 0 then "false"
    when "unset", "auto" then "unset"
    when nil, "" then DEFAULTS.fetch("enable_thinking")
    else
      DEFAULTS.fetch("enable_thinking")
    end
  end
end
