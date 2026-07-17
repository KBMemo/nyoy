# frozen_string_literal: true

module AgentGraph
  class DiagnosticRunSummary < RunSummaryBase
    def build
      common_fields.merge(
        note: state["note"],
        final_answer: state["final_answer"],
        approval: state["approval"],
        errors: state["errors"]
      ).merge(status_fields)
    end
  end
end
