# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Pack gathered evidence into an internal summary (no LLM).
    # The user-facing reply is generated later by FinalizeAnswer.
    class SynthesizeDraft
      def call(state:, run:, chat:)
        synthesizer = AgentGraph::EvidenceSynthesizer.new(chat)
        evidence = synthesizer.evidence_pack(state)
        draft = synthesizer.fallback_answer(evidence)
        if draft.blank?
          return AgentGraph::NodeResult.fail(
            "empty draft",
            updates: {
              "errors" => Array(state["errors"]) + [ {
                "node" => "synthesize_draft",
                "code" => "EMPTY_DRAFT",
                "message" => "evidence pack produced no content"
              } ]
            }
          )
        end

        updates = {
          "draft" => draft,
          "draft_truncated" => false,
          "draft_thinking" => nil,
          "draft_synthesis" => {
            "source" => "evidence_pack",
            "model_id" => nil,
            "thinking" => nil
          },
          "approval" => "not_required"
        }

        AgentGraph::NodeResult.next(updates: updates)
      end
    end
  end
end
