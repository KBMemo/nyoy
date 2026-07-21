# frozen_string_literal: true

module LlmUsageAssignmentSeeds
  AGENT_USAGE_KEYS = %w[
    agent.intent
    agent.planner
    agent.evidence_evaluator
    agent.draft
    agent.final_answer
  ].freeze
  module_function

  def seed!
    ChatModelCatalog.seed!
    chat_model = ChatModelCatalog.default_model
    style_model = chat_model
    utility_model = model_for_chat_connection("llama_cpp")
    vision_model = model_for_connection("vision_llama", capabilities: [ "chat" ], input_modalities: %w[text image])
    embedding_model = model_for_connection("embeddings", capabilities: [ "embedding" ], input_modalities: [ "text" ])

    create_missing!("chat.default", chat_model)
    AGENT_USAGE_KEYS.each { |usage_key| create_missing!(usage_key, chat_model) }
    create_missing!("vision.image_understanding", vision_model)
    create_missing!("embedding.memo_knowledge", embedding_model)
    create_missing!("embedding.prompt_knowledge", embedding_model)
    create_missing!("image.style_plan", style_model)
    create_missing!("image.direct_prompt", style_model)
    create_missing!("utility.chat_history_summary", utility_model)
    create_missing!("utility.memo_chunk_compression", utility_model)
    create_missing!("utility.sd_prompt_translation", utility_model)
  end

  def create_missing!(usage_key, model, fallback_model: nil, sampling_preset: nil)
    return unless model

    assignment = LlmUsageAssignment.find_or_initialize_by(usage_key: usage_key)
    return assignment if assignment.persisted?

    assignment.assign_attributes(model:, fallback_model:, llm_sampling_preset: sampling_preset)
    assignment.save!
    assignment
  end

  def model_for_chat_connection(connection_key)
    connection = ServiceConnection.resolve(connection_key)
    return unless connection&.enabled?
    return unless connection&.server_model.present?

    model_by_model_id(connection.server_model)
  end

  def model_for_connection(connection_key, capabilities:, input_modalities:)
    connection = ServiceConnection.resolve(connection_key)
    return unless connection&.enabled?
    return unless connection&.server_model.present?

    model = Model.find_or_initialize_by(provider: "openai", model_id: connection.server_model)
    model.assign_attributes(
      name: model.name.presence || connection.server_model,
      family: model.family.presence || "local",
      capabilities: (Array(model.capabilities) | capabilities),
      modalities: model.modalities.to_h.deep_merge(
        "input" => (Array(model.modalities.to_h["input"]) | input_modalities),
        "output" => (Array(model.modalities.to_h["output"]) | [ "text" ])
      ),
      metadata: model.metadata.to_h.merge(
        "api_base" => connection.base_url,
        "connection_key" => connection.key
      )
    )
    model.save!
    model
  end

  def model_by_model_id(model_id)
    return if model_id.blank?

    Model.find_by(provider: "openai", model_id: model_id)
  end
end
