# frozen_string_literal: true

class LlmUsageResolver
  Resolution = Data.define(:usage_key, :assignment, :model, :connection, :sampling_preset)

  class << self
    def resolve(usage_key)
      assignment = LlmUsageAssignment.enabled.includes(:model, :fallback_model, :llm_sampling_preset)
        .find_by(usage_key: usage_key.to_s)
      return unless assignment

      resolve_model(assignment, assignment.model) || resolve_model(assignment, assignment.fallback_model)
    end

    def model_for(usage_key, legacy: nil)
      resolve(usage_key)&.model || legacy
    end

    def llama_client_for(usage_key, legacy_connection_key: :llama_cpp)
      resolution = resolve(usage_key)
      return client_for(resolution) if resolution

      LlamaCppClient.new(
        base_url: NyoyConnectionStore.url(legacy_connection_key),
        model: NyoyConnectionStore.server_model(legacy_connection_key),
        api_token: NyoyConnectionStore.api_token(legacy_connection_key)
      )
    end

    private

    def resolve_model(assignment, model)
      return unless model

      connection_key = model.metadata.to_h["connection_key"].to_s.presence
      connection = ServiceConnection.resolve(connection_key) if connection_key
      connection = nil unless connection&.enabled?
      return unless connection

      Resolution.new(
        usage_key: assignment.usage_key,
        assignment: assignment,
        model: model,
        connection: connection,
        sampling_preset: assignment.llm_sampling_preset
      )
    end

    def client_for(resolution)
      LlamaCppClient.new(
        base_url: resolution.connection.base_url,
        model: resolution.model.model_id,
        api_token: resolution.connection.api_token
      )
    end
  end
end
