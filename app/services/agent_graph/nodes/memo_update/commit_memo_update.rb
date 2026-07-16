# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoUpdate
      class CommitMemoUpdate
        def call(state:, run:, chat:)
          return AgentGraph::NodeResult.next if state["memo_uid"].present?

          draft = state["memo_draft"]
          unless draft.is_a?(Hash) && draft["memo_ref"].present? && draft["updated_at"].present?
            return AgentGraph::NodeResult.fail("missing memo_draft for update")
          end

          result = ChatTools::UpdateMemo.new(chat: chat).execute(
            memo_ref: draft["memo_ref"].to_s,
            updated_at: draft["updated_at"].to_s,
            body: draft["body"].presence,
            append_body: draft["append_body"].presence,
            title: draft["title"].presence
          )

          if result.is_a?(Hash) && result["error"].present?
            return AgentGraph::NodeResult.fail(
              "update_memo failed: #{result["error"]}",
              updates: error_update(state, "UPDATE_MEMO_FAILED", result["error"])
            )
          end

          uid = result.is_a?(Hash) ? (result["uid"].presence || result["id"]&.to_s || draft["memo_ref"]) : draft["memo_ref"]
          AgentGraph::NodeResult.next(
            updates: {
              "memo_uid" => uid.to_s,
              "memo_result" => result.is_a?(Hash) ? result : { "raw" => result }
            }
          )
        end

        private

        def error_update(state, code, message)
          {
            "errors" => Array(state["errors"]) + [ {
              "code" => code,
              "message" => message.to_s
            } ]
          }
        end
      end
    end
  end
end
