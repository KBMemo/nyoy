# frozen_string_literal: true

class LlamaServerUsageResolver
  MODEL_USAGES = {
    research_draft_model: "AgentGraph draft",
    research_planner_model: "AgentGraph planner",
    agent_graph_intent_model: "AgentGraph intent",
    evidence_evaluator_model: "AgentGraph evidence evaluator",
    final_answer_model: "AgentGraph final answer"
  }.freeze

  def self.labels_for(connection)
    labels = []
    labels << "既定Chat" if AppSetting.default_chat_connection_key == connection.key
    labels << "style plan" if AppSetting.default_style_plan_connection_key == connection.key
    labels << "画像理解" if connection.key == "vision_llama"
    labels << "埋め込み" if connection.key == "embeddings"
    MODEL_USAGES.each do |resolver, label|
      model = AppSetting.public_send(resolver)
      labels << label if model&.metadata&.dig("connection_key") == connection.key
    end
    labels
  end

  def self.descriptions_for_server(manager, server_id)
    manager.managed_connections.enabled.where(managed_server_id: server_id).ordered.map do |connection|
      labels = labels_for(connection)
      description = "#{connection.name} (#{connection.key})"
      labels.any? ? "#{description}: #{labels.join(', ')}" : description
    end
  end
end
