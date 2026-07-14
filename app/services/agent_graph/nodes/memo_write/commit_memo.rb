# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoWrite
      # Persist via ChatTools::CreateMemo. Idempotent when memo_uid already set.
      class CommitMemo
        def call(state:, run:, chat:)
          if state["memo_uid"].present?
            return AgentGraph::NodeResult.next("finalize_reply")
          end

          draft = state["memo_draft"]
          unless draft.is_a?(Hash) && draft["body"].to_s.present?
            return AgentGraph::NodeResult.fail("missing memo_draft for commit")
          end

          result = ChatTools::CreateMemo.new(chat: chat).execute(
            body: draft["body"].to_s,
            title: draft["title"].presence
          )

          if result.is_a?(Hash) && result["error"].present?
            return AgentGraph::NodeResult.fail(
              "create_memo failed: #{result["error"]}",
              updates: {
                "errors" => Array(state["errors"]) + [ {
                  "code" => "CREATE_MEMO_FAILED",
                  "message" => result["error"].to_s
                } ]
              }
            )
          end

          uid = result.is_a?(Hash) ? (result["uid"].presence || result["id"]&.to_s) : nil
          if uid.blank?
            return AgentGraph::NodeResult.fail(
              "create_memo returned no uid",
              updates: {
                "errors" => Array(state["errors"]) + [ {
                  "code" => "CREATE_MEMO_EMPTY",
                  "message" => result.inspect
                } ]
              }
            )
          end

          AgentGraph::NodeResult.next(
            "finalize_reply",
            updates: {
              "memo_uid" => uid.to_s,
              "memo_result" => result.is_a?(Hash) ? result : { "raw" => result }
            }
          )
        end
      end
    end
  end
end
