# frozen_string_literal: true

module StylePlanModelCatalog
  JSON_SCHEMA_CONNECTIONS = %w[llama_cpp openai].freeze

  module_function

  def definitions
    ChatModelCatalog.definitions
  end

  def connection_keys
    definitions.map(&:connection_key).uniq
  end

  def default_connection_key
    AppSetting.default_style_plan_connection_key.presence || connection_keys.first || "llama_cpp"
  end

  def options_for_select
    definitions.map { |definition| [ option_label(definition), definition.connection_key ] }.uniq(&:last)
  end

  def label_for(connection_key)
    definition = definitions.find { |item| item.connection_key == connection_key }
    return definition.name if definition

    ServiceConnection.find_by(key: connection_key)&.name || connection_key
  end

  def prompt_conversion_settings(connection_key)
    connection = ServiceConnection.find_by(key: connection_key.to_s)
    PromptConversionSettings.from(connection&.settings)
  end

  def json_schema_supported?(connection_key)
    key = connection_key.to_s
    return true if JSON_SCHEMA_CONNECTIONS.include?(key)
    return true if key.match?(ServiceConnection::CUSTOM_LLM_KEY_FORMAT)

    false
  end

  def json_schema_enabled?(connection_key)
    return false unless Rails.application.config.x.nyoy.llama_json_schema

    settings = prompt_conversion_settings(connection_key)
    case settings.json_schema
    when "on" then true
    when "off" then false
    else
      json_schema_supported?(connection_key)
    end
  end

  def model_for(connection_key)
    key = connection_key.to_s
    connection = ServiceConnection.find_by(key: key)

    if connection&.openai?
      settings = OpenaiChatModelSettings.from(connection.settings)
      settings.enabled.first ||
        connection.server_model.presence ||
        NyoyConnectionStore.server_model(key)
    else
      NyoyConnectionStore.server_model(key)
    end
  end

  def client_for(connection_key: nil)
    key = connection_key.presence || default_connection_key
    unless ServiceConnection.chat_keys.include?(key)
      raise StylePlanGenerator::Error, "不明な接続です: #{key}"
    end
    unless NyoyConnectionStore.enabled?(key)
      raise StylePlanGenerator::Error, "接続 #{key} が無効です"
    end

    model = model_for(key)
    raise StylePlanGenerator::Error, "接続 #{key} のモデル名が未設定です" if model.blank?

    LlamaCppClient.new(
      base_url: NyoyConnectionStore.url(key),
      model: model,
      api_token: NyoyConnectionStore.api_token(key)
    )
  end

  def option_label(definition)
    connection = ServiceConnection.find_by(key: definition.connection_key)
    connection_name = connection&.name || definition.connection_key
    return connection_name if connection_name == definition.name

    "#{connection_name} — #{definition.name}"
  end
end
