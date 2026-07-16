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
            "thinking" => nil,
            "evidence" => evidence_counts(evidence)
          },
          "approval" => "not_required"
        }

        AgentGraph::NodeResult.next(updates: updates)
      end

      private

      def evidence_counts(evidence)
        {
          "memo" => evidence[:memo].present? ? 1 : 0,
          "search_results" => Array(evidence[:search_results]).sum { |payload| Array(payload["results"]).size },
          "fetched_pages" => Array(evidence[:fetched_pages]).size,
          "errors" => Array(evidence[:errors]).size
        }
      end
    end
  end
end
