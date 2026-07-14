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

  def self.effective_for(chat)
    stored = from(chat.llm_params)
    return stored unless stored.to_h.empty?

    from(AppSetting.default_chat_llm_params)
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
