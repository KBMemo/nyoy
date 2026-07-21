# frozen_string_literal: true

class LlamaServerAlert
  class << self
    def enabled?
      webhook_enabled? || zabbix_enabled?
    end

    def webhook_enabled?
      webhook_url.present?
    end

    def zabbix_enabled?
      zabbix_server.present? && zabbix_host.present?
    end

    def webhook_url
      Rails.application.config.x.nyoy.llama_server_alert_webhook_url.to_s
    end

    def webhook_token
      Rails.application.config.x.nyoy.llama_server_alert_webhook_token.to_s
    end

    def zabbix_server
      Rails.application.config.x.nyoy.llama_server_alert_zabbix_server.to_s
    end

    def zabbix_port
      Rails.application.config.x.nyoy.llama_server_alert_zabbix_port.to_i
    end

    def zabbix_host
      Rails.application.config.x.nyoy.llama_server_alert_zabbix_host.to_s
    end

    def zabbix_key_prefix
      Rails.application.config.x.nyoy.llama_server_alert_zabbix_key_prefix.to_s
    end
  end
end
