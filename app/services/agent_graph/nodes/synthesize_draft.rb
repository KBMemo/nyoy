# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Build a draft answer from collected evidence, then hand off to approval.
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

        AgentGraph::NodeResult.next(
          "await_approval",
          updates: {
            "draft" => draft,
            "draft_truncated" => truncated,
            "approval" => nil
          }
        )
      end
    end
  end
end
