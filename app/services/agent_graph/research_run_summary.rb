# frozen_string_literal: true

module AgentGraph
  class ResearchRunSummary < RunSummaryBase
    def build
      common_fields.merge(
        question: state["question"],
        routing: state["routing"] || {},
        draft: state["draft"],
        final_answer: state["final_answer"],
        approval: state["approval"],
        assistant_message_id: state["assistant_message_id"],
        plan: state["plan"],
        planning: state["planning"] || {},
        evidence_review: state["evidence_review"] || {},
        budget: state["budget"] || {},
        errors: state["errors"]
      ).merge(status_fields)
    end
  end
end
