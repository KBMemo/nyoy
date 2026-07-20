# frozen_string_literal: true

class LlamaServerAlert
  class << self
    def enabled?
      webhook_url.present?
    end

    def webhook_url
      Rails.application.config.x.nyoy.llama_server_alert_webhook_url.to_s
    end

    def webhook_token
      Rails.application.config.x.nyoy.llama_server_alert_webhook_token.to_s
    end
  end
end
