# frozen_string_literal: true

class LlmUsageAssignmentAudit
  class << self
    def call
      assignments = LlmUsageAssignment.includes(
        model: :service_connection,
        fallback_model: :service_connection,
        llm_sampling_preset: []
      ).index_by(&:usage_key)

      LlmUsageCatalog.all.map { |definition| audit(definition, assignments[definition.key]) }
    end

    private

    def audit(definition, assignment)
      return base_report(definition).merge("status" => "missing", "issues" => [ "assignment_missing" ]) unless assignment

      primary = model_report(definition, assignment.model)
      fallback = model_report(definition, assignment.fallback_model)
      issues = assignment_issues(assignment, primary, fallback)

      base_report(definition).merge(
        "status" => status_for(assignment, primary, fallback, issues),
        "enabled" => assignment.enabled?,
        "primary" => primary,
        "fallback" => fallback,
        "sampling_preset" => assignment.llm_sampling_preset&.key,
        "issues" => issues
      )
    end

    def base_report(definition)
      {
        "usage_key" => definition.key,
        "label" => definition.label,
        "required_capabilities" => definition.capabilities.map(&:to_s)
      }
    end

    def model_report(definition, model)
      return nil unless model

      connection = model.service_connection
      missing = definition.capabilities - LlmModelCapabilities.for(model)
      alias_matches = runtime_alias_matches?(model, connection)
      {
        "id" => model.id,
        "model_id" => model.model_id,
        "missing_capabilities" => missing.map(&:to_s),
        "connection_key" => connection&.key,
        "connection_enabled" => connection&.enabled? == true,
        "runtime_alias_matches" => alias_matches,
        "available" => missing.empty? && alias_matches && connection&.model_endpoint? == true && connection.enabled?
      }
    end

    def assignment_issues(assignment, primary, fallback)
      issues = []
      issues << "assignment_disabled" unless assignment.enabled?
      unless assignment.valid?
        issues.concat(assignment.errors.map { |error| "#{error.attribute}: #{error.message}" })
      end
      issues << "primary_unavailable" unless primary&.fetch("available")
      issues << "primary_alias_drift" if primary && !primary.fetch("runtime_alias_matches")
      issues << "fallback_unavailable" if fallback && !fallback.fetch("available")
      issues << "fallback_alias_drift" if fallback && !fallback.fetch("runtime_alias_matches")
      issues.uniq
    end

    def status_for(assignment, primary, fallback, issues)
      return "disabled" unless assignment.enabled?
      return "invalid" if issues.any? { |issue| issue.include?(": ") }
      return "healthy" if primary&.fetch("available")
      return "degraded" if fallback&.fetch("available")

      "unavailable"
    end

    def runtime_alias_matches?(model, connection)
      return true unless connection&.adapter == "llama_cpp"

      model.model_id.to_s == connection.server_model.to_s
    end
  end
end
