# frozen_string_literal: true

module StylePlanModelCatalog
  module_function

  def definitions
    ChatModelCatalog.definitions
  end

  def connection_keys
    definitions.map(&:connection_key)
  end

  def default_connection_key
    preferred = Rails.application.config.x.nyoy.style_plan_connection_key.to_s
    return preferred if connection_keys.include?(preferred)

    connection_keys.first || "llama_cpp"
  end

  def options_for_select
    definitions.map { |definition| [definition.name, definition.connection_key] }
  end

  def label_for(connection_key)
    definitions.find { |definition| definition.connection_key == connection_key }&.name || connection_key
  end

  def client_for(connection_key: nil)
    key = connection_key.presence || default_connection_key
    unless ServiceConnection.chat_keys.include?(key)
      raise StylePlanGenerator::Error, "不明な接続です: #{key}"
    end
    unless NyoyConnectionStore.enabled?(key)
      raise StylePlanGenerator::Error, "接続 #{key} が無効です"
    end

    LlamaCppClient.new(
      base_url: NyoyConnectionStore.url(key),
      model: NyoyConnectionStore.server_model(key)
    )
  end
end
