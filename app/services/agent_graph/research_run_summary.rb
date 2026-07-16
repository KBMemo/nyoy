# frozen_string_literal: true

module AgentGraph
  class ResearchRunSummary < RunSummaryBase
    def build
      common_fields.merge(
        question: state["question"],
        draft: state["draft"],
        final_answer: state["final_answer"],
        approval: state["approval"],
        assistant_message_id: state["assistant_message_id"],
        plan: state["plan"],
        errors: state["errors"]
      ).merge(status_fields)
    end
  end
end
