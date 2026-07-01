# frozen_string_literal: true

module NyoyConnectionStore
  FALLBACKS = {
    llama_cpp: { url: :llama_cpp_url, model: :llama_model },
    gpt_oss: { url: :gpt_oss_llama_cpp_url, model: :gpt_oss_model, url_fallback: :llama_cpp_url },
    vision_llama: { url: :vision_llama_cpp_url, model: :vision_llama_model },
    embeddings: { url: :embeddings_url, model: :embeddings_model },
    sd_cpp: { url: :sd_cpp_url },
    sd_switchd: { url: :sd_switchd_url, token: :sd_switchd_token }
  }.freeze

  class << self
    def url(key)
      record = connection(key)
      return record.base_url if record&.enabled? && record.base_url.present?

      env_value(key, :url)
    end

    def server_model(key)
      record = connection(key)
      return record.server_model if record&.enabled? && record.server_model.present?

      env_value(key, :model)
    end

    def api_token(key)
      record = connection(key)
      return record.api_token if record&.enabled? && record.api_token.present?

      env_value(key, :token)
    end

    def enabled?(key)
      record = connection(key)
      return record.enabled? if record

      true
    end

    def clear_cache!
      @cache = {}
    end

    private

    def connection(key)
      return nil unless table_ready?

      @cache ||= {}
      @cache[key.to_s] ||= ServiceConnection.find_by(key: key.to_s)
    end

    def table_ready?
      ServiceConnection.table_exists?
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def env_value(key, attribute)
      mapping = FALLBACKS.fetch(key.to_sym)
      config = Rails.application.config.x.nyoy

      if attribute == :url
        primary = config.public_send(mapping[:url])
        fallback_key = mapping[:url_fallback]
        return primary.presence || (fallback_key && config.public_send(fallback_key))
      end

      token_key = mapping[:token]
      return config.public_send(token_key) if attribute == :token && token_key

      model_key = mapping[:model]
      config.public_send(model_key) if attribute == :model && model_key
    end
  end
end
