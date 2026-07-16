# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoWrite
      # Confirm save to the chat as an assistant message.
      class FinalizeReply
        def call(state:, run:, chat:)
          uid = state["memo_uid"].to_s.presence
          if uid.blank?
            return AgentGraph::NodeResult.fail("missing memo_uid for finalize")
          end

          title = state.dig("memo_draft", "title").presence || "メモ"
          answer = "徒然に保存しました。\n\n- タイトル: #{title}\n- uid: `#{uid}`"
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
