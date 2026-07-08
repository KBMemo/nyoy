# frozen_string_literal: true

module ChatModelCatalog
  ModelDefinition = Data.define(:model_id, :name, :api_base, :connection_key)

  module_function

  def definitions
    ServiceConnection.chat_backends.enabled.ordered.flat_map do |connection|
      model_ids_for(connection).filter_map do |model_id|
        ModelDefinition.new(
          model_id: model_id,
          name: display_name(connection, model_id),
          api_base: connection.base_url,
          connection_key: connection.key
        )
      end
    end
  end

  def model_ids_for(connection)
    if connection.openai?
      Array(connection.settings&.dig("chat_models")).compact_blank.presence ||
        [ connection.server_model ].compact_blank
    else
      model_id = connection.server_model.presence || NyoyConnectionStore.server_model(connection.key)
      model_id.present? ? [ model_id ] : []
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
    seed! if ServiceConnection.chat_backends.enabled.any?

    ServiceConnection.chat_backends.enabled.ordered.filter_map do |connection|
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
        context_window: connection&.openai? ? 128_000 : 8192,
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
