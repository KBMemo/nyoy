# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoUpdate
      class DraftMemoUpdate
        def call(state:, run:, chat:)
          original = state["original_memo"].is_a?(Hash) ? state["original_memo"] : {}
          updated_at = original["updated_at"].to_s.presence
          if updated_at.blank?
            return AgentGraph::NodeResult.fail("get_memo returned no updated_at")
          end

          memo_draft, draft, metadata = AgentGraph::RoleServices.fetch(:memo_writer).call(
            action: :update,
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
