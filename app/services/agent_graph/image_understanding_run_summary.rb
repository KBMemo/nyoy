# frozen_string_literal: true

module AgentGraph
  class ImageUnderstandingRunSummary < RunSummaryBase
    def build
      common_fields.merge(
        question: state["question"],
        plan: state["plan"] || {},
        image_source: state["image_source"],
        analysis: state["analysis"],
        final_answer: state["final_answer"],
        assistant_message_id: state["assistant_message_id"],
        errors: state["errors"]
      ).merge(status_fields)
    end
  end
end
