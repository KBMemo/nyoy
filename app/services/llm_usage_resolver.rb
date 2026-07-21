# frozen_string_literal: true

class LlmUsageResolver
  class MissingAssignmentError < StandardError; end

  Resolution = Data.define(:usage_key, :assignment, :model, :connection, :sampling_preset)

  class << self
    def resolve(usage_key)
      assignment = LlmUsageAssignment.enabled.includes(:model, :fallback_model, :llm_sampling_preset)
        .find_by(usage_key: usage_key.to_s)
      return unless assignment

      resolve_model(assignment, assignment.model) || resolve_model(assignment, assignment.fallback_model)
    end

    def model_for(usage_key)
      resolve(usage_key)&.model
    end

    def llama_client_for(usage_key)
      resolution = resolve(usage_key)
      raise MissingAssignmentError, "LLM usage assignment is unavailable: #{usage_key}" unless resolution

      client_for(resolution)
    end

    private

    def resolve_model(assignment, model)
      return unless model

      connection = model.service_connection
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
