# frozen_string_literal: true

module AgentGraph
  class MemoWriteRunSummary < RunSummaryBase
    def build
      common_fields.merge(
        instruction: state["instruction"],
        draft: state["draft"],
        memo_draft: memo_draft,
        memo_uid: state["memo_uid"],
        final_answer: state["final_answer"],
        approval: state["approval"],
        assistant_message_id: state["assistant_message_id"],
        errors: state["errors"]
      ).merge(status_fields)
    end
  end
end
