# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoWrite
      # Build display draft + structured memo_draft (no LLM polish).
      class DraftMemo
        def call(state:, run:, chat:)
          body = state["source_body"].to_s.strip
          if body.blank?
            return AgentGraph::NodeResult.fail("missing body for draft_memo")
          end

          memo_draft, draft, metadata = AgentGraph::RoleServices.fetch(:memo_writer).call(
            action: :create,
            state: state,
            run: run,
            chat: chat
          )

          AgentGraph::NodeResult.next(
            updates: {
              "memo_draft" => memo_draft,
              "draft" => draft,
              "memo_draft_meta" => writer_metadata(metadata)
            }
          )
        end

        private

        def writer_metadata(metadata)
          metadata.to_h.stringify_keys.merge(
            "role" => "memo_writer",
            "profile" => AgentGraph::RoleServices.active_profile_for(:memo_writer).to_s
          )
        end
      end
    end
  end
end
