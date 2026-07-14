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
          message = create_assistant_message!(chat, answer)
          ChatUiBroadcaster.message_upsert(message)
          AgentGraph::ApprovalBroadcaster.clear!(chat)

          AgentGraph::NodeResult.end(
            updates: {
              "final_answer" => answer,
              "assistant_message_id" => message.id
            }
          )
        end

        private

        def create_assistant_message!(chat, answer)
          Message.suppressing_turbo_broadcasts do
            chat.messages.create!(role: :assistant, content: answer)
          end
        end
      end
    end
  end
end
