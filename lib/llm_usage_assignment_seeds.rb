# frozen_string_literal: true

module LlmUsageAssignmentSeeds
  AGENT_MODEL_COLUMNS = {
    "agent.intent" => :agent_graph_intent_model_id,
    "agent.planner" => :research_planner_model_id,
    "agent.evidence_evaluator" => :evidence_evaluator_model_id,
    "agent.draft" => :research_draft_model_id,
    "agent.final_answer" => :final_answer_model_id
  }.freeze

  module_function

  def seed!
    ChatModelCatalog.seed!
    setting = AppSetting.instance
    chat_model = model_for_chat_connection(AppSetting.default_chat_connection_key)
    style_model = model_for_chat_connection(AppSetting.default_style_plan_connection_key)
    utility_model = model_for_chat_connection("llama_cpp")
    vision_model = model_for_connection("vision_llama", capabilities: [ "chat" ], input_modalities: %w[text image])
    embedding_model = model_for_connection("embeddings", capabilities: [ "embedding" ], input_modalities: [ "text" ])

    create_missing!("chat.default", chat_model, sampling_preset: default_sampling_preset(setting))
    AGENT_MODEL_COLUMNS.each do |usage_key, column|
      preferred = model_by_model_id(setting.public_send(column)) || chat_model
      fallback = chat_model if preferred && chat_model && preferred != chat_model
      create_missing!(usage_key, preferred, fallback_model: fallback)
    end
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
    connection = ServiceConnection.enabled.find_by(key: connection_key)
    return unless connection&.server_model.present?

    model_by_model_id(connection.server_model)
  end

  def model_for_connection(connection_key, capabilities:, input_modalities:)
    connection = ServiceConnection.enabled.find_by(key: connection_key)
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

  def default_sampling_preset(setting)
    key = setting.default_llm_sampling_preset_key.to_s.presence
    LlmSamplingPreset.enabled.find_by(key: key) if key
  end
end
