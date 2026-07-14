# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Build a draft answer from collected evidence, then approve or finalize.
    class SynthesizeDraft
      def call(state:, run:, chat:)
        draft, truncated = AgentGraph::EvidenceSynthesizer.new(chat).call(state)
        if draft.blank?
          return AgentGraph::NodeResult.fail(
            "empty draft",
            updates: {
              "errors" => Array(state["errors"]) + [ {
                "node" => "synthesize_draft",
                "code" => "EMPTY_DRAFT",
                "message" => "draft synthesis produced no content"
              } ]
            }
          )
        end

        next_state = state.merge(
          "draft" => draft,
          "draft_truncated" => truncated
        )
        goto = AgentGraph::ResearchRouting.after_synthesize(next_state)
        updates = {
          "draft" => draft,
          "draft_truncated" => truncated,
          "approval" => goto == "await_approval" ? nil : "not_required"
        }

        AgentGraph::NodeResult.next(goto, updates: updates)
      end
    end
  end
end
