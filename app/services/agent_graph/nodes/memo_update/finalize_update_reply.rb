# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoUpdate
      class FinalizeUpdateReply
        def call(state:, run:, chat:)
          uid = state["memo_uid"].to_s.presence
          return AgentGraph::NodeResult.fail("missing memo_uid for finalize") if uid.blank?

          mode = state.dig("memo_draft", "mode") == "replace" ? "本文を更新" : "本文を追記"
          answer = "徒然メモを更新しました。\n\n- 操作: #{mode}\n- uid: `#{uid}`"
          message = AgentGraph::AssistantMessagePublisher.call(
            chat,
            content: answer
          )

          AgentGraph::NodeResult.end(
            updates: {
              "final_answer" => answer,
              "assistant_message_id" => message.id
            }
          )
        end
      end
    end
  end
end
