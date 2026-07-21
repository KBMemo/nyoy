# frozen_string_literal: true

module ChatModelCatalog
  ModelDefinition = Data.define(:model_id, :name, :api_base, :connection_key)

  module_function

  def definitions
    available_chat_backends.flat_map do |connection|
      definitions_for(connection)
    end
  end

  def configured_definitions
    ServiceConnection.model_endpoints.enabled.ordered.flat_map do |connection|
      definitions_for(connection)
    end
  end

  def definitions_for(connection)
    model_ids_for(connection).filter_map do |model_id|
      ModelDefinition.new(
        model_id: model_id,
        name: display_name(connection, model_id),
        api_base: connection.base_url,
        connection_key: connection.key
      )
    end
  end

  def model_ids_for(connection)
    if connection.openai?
      Array(connection.settings&.dig("chat_models")).compact_blank.presence ||
        [ connection.server_model ].compact_blank
    elsif connection.generative_model_endpoint?
      model_id = connection.server_model.presence || NyoyConnectionStore.server_model(connection.key)
      model_id.present? ? [ model_id ] : []
    else
      []
    end
  end

  def display_name(connection, model_id)
    model_id
  end

  def model_ids
    definitions.map(&:model_id)
  end

  # Returns option groups for chat model select: [[connection_name, [[model_name, id], ...]], ...]
  def grouped_model_options
    seed! if ServiceConnection.model_endpoints.enabled.any?

    available_chat_backends.filter_map do |connection|
      model_ids = model_ids_for(connection)
      next if model_ids.empty?

      models = Model.where(provider: "openai", model_id: model_ids).order(:name)
      next if models.empty?

      [ connection.name, models.map { |record| [ record.name, record.id ] } ]
    end
  end

  def default_connection_key
    AppSetting.default_chat_connection_key.presence || definitions.first&.connection_key
  end

  def default_model
    assigned = LlmUsageResolver.model_for("chat.default")
    return assigned if assigned

    key = default_connection_key
    definition = definitions.find { |item| item.connection_key == key } || definitions.first
    return nil unless definition

    Model.find_by(provider: "openai", model_id: definition.model_id)
  end

  def seed!
    definitions.each do |definition|
      connection = ServiceConnection.find_by(key: definition.connection_key)
      record = Model.find_or_initialize_by(provider: "openai", model_id: definition.model_id)
      record.assign_attributes(
        name: definition.name,
        family: connection&.openai? ? "openai" : "local",
        context_window: context_window_for(connection),
        capabilities: [ "chat" ],
        modalities: { "input" => [ "text" ], "output" => [ "text" ] },
        metadata: {
          "api_base" => definition.api_base,
          "connection_key" => definition.connection_key
        }
      )
      record.save!
    end
  end

  def context_window_for(connection)
    return 128_000 if connection&.openai?

    n_ctx = n_ctx_from_props(connection&.base_url)
    return n_ctx if n_ctx.to_i.positive?

    8192
  end

  def available_chat_backends
    ServiceConnection.model_endpoints.enabled.ordered.select do |connection|
      next false unless connection.generative_model_endpoint?

      LlamaServerAvailability.available?(connection)
    end
  end

  def n_ctx_from_props(base_url)
    base = base_url.to_s.sub(%r{/\z}, "")
    return nil if base.blank?

    props = LlamaCppClient.new(base_url: base).props
    value = props.dig("default_generation_settings", "n_ctx") || props["n_ctx"]
    count = Integer(value)
    count.positive? ? count : nil
  rescue ArgumentError, TypeError, LlamaCppClient::Error
    nil
  end

  def context_for(model_record)
    connection_key = model_record&.metadata&.dig("connection_key")
    api_base = if connection_key.present?
      NyoyConnectionStore.url(connection_key)
    else
      model_record&.metadata&.dig("api_base")
    end
    api_base = api_base.presence || NyoyConnectionStore.url(:llama_cpp)
    normalized = api_base.sub(%r{/\z}, "")

    api_key = if connection_key == "openai"
      NyoyConnectionStore.api_token(:openai).presence || RubyLLM.config.openai_api_key
    else
      RubyLLM.config.openai_api_key
    end

    config = RubyLLM::Configuration.new
    config.openai_api_base = "#{normalized}/v1"
    config.openai_api_key = api_key
    config.openai_use_system_role = RubyLLM.config.openai_use_system_role
    config.request_timeout = RubyLLM.config.request_timeout
    config.use_new_acts_as = RubyLLM.config.use_new_acts_as

    RubyLLM::Context.new(config)
  end
end
