# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Pack gathered evidence into an internal summary (no LLM).
    # The user-facing reply is generated later by FinalizeAnswer.
    class SynthesizeDraft
      def call(state:, run:, chat:)
        draft, truncated, meta = AgentGraph::RoleServices.fetch(:draft).call(
          state: state,
          run: run,
          chat: chat
        )
        meta = (meta || {}).stringify_keys.merge(
          "role" => "draft",
          "profile" => AgentGraph::RoleServices.active_profile_for(:draft).to_s
        )

        if draft.blank?
          return AgentGraph::NodeResult.fail(
            "empty draft",
            updates: {
              "errors" => Array(state["errors"]) + [ {
                "node" => "synthesize_draft",
                "code" => "EMPTY_DRAFT",
                "message" => "evidence pack produced no content"
              } ],
              "draft_synthesis" => meta
            }
          )
        end

        updates = {
          "draft" => draft,
          "draft_truncated" => truncated == true,
          "draft_thinking" => meta["thinking"].presence,
          "draft_synthesis" => meta,
          "approval" => "not_required"
        }

        AgentGraph::NodeResult.next(updates: updates)
      end
    end
  end
end
