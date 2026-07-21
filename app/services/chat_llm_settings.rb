# frozen_string_literal: true

class ChatLlmSettings
  RANGES = LlmSamplingParams::RANGES

  attr_reader :sampling

  delegate(*LlmSamplingParams::KEYS.map(&:to_sym), to: :sampling)

  def self.from(hash)
    new(hash)
  end

  def self.normalize(hash)
    from(hash).to_h
  end

  def self.apply!(llm_chat, chat:)
    settings = effective_for(chat)
    settings.apply!(llm_chat)
  end

  # App default preset < connection profile sampling < per-chat llm_params.
  def self.effective_for(chat)
    from(merge_layers(defaults_for(model: chat.model_association).to_h, chat.llm_params))
  end

  # Defaults for a model before per-chat overrides (new chat form / seed).
  def self.defaults_for(model: nil)
    from(merge_layers(default_sampling_for(model), connection_llm_params_for(model)))
  end

  def self.default_sampling_for(model)
    resolution = LlmUsageResolver.resolve("chat.default")
    preset = resolution&.sampling_preset
    if preset && resolution.model == model
      normalize(preset.sampling_params.to_h_compact)
    else
      AppSetting.default_chat_llm_params
    end
  end

  def self.connection_llm_params_for(model)
    key = model&.metadata&.dig("connection_key").to_s.presence
    return {} if key.blank?

    connection = ServiceConnection.enabled.find_by(key: key)
    return {} unless connection&.supports_prompt_conversion_settings?

    normalize(connection.prompt_conversion_settings.sampling.to_h_compact)
  end

  def self.merge_layers(*layers)
    layers.compact.reduce({}) do |acc, layer|
      LlmSamplingParams.merge(acc, layer).to_h_compact
    end
  end

  def initialize(hash = nil)
    @sampling = LlmSamplingParams.from(hash)
  end

  def apply!(llm_chat)
    llm_chat.with_temperature(temperature) unless temperature.nil?

    params = to_request_params
    return llm_chat if params.empty?

    existing = llm_chat.instance_variable_get(:@params) || {}
    llm_chat.with_params(**existing.merge(params))
  end

  def to_h
    sampling.to_h_compact
  end

  def to_request_params
    sampling.to_request_params.tap do |params|
      params[:max_tokens] = max_tokens unless max_tokens.nil?
    end
  end

  def form_value(key)
    public_send(key)
  end
end
