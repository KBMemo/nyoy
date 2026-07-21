# frozen_string_literal: true

class LlamaServerUsageResolver
  def self.labels_for(connection)
    labels = LlmUsageAssignment.enabled.includes(:model, :fallback_model).filter_map do |assignment|
      models = [ assignment.model, assignment.fallback_model ].compact
      next unless models.any? { |model| model.metadata.to_h["connection_key"] == connection.key }

      LlmUsageCatalog.fetch(assignment.usage_key).label
    end.uniq
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
