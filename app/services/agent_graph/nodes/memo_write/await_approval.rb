# frozen_string_literal: true

module AgentGraph
  module Nodes
    module MemoWrite
      # Always interrupt unless auto_approve. Reject ends without replan.
      class AwaitApproval
        REJECTED_MESSAGE = "メモ保存は却下されました。内容を直してから、もう一度「徒然に保存して」と伝えてください。"

        def call(state:, run:, chat:)
          case state["approval"].to_s
          when "approved", "not_required"
            AgentGraph::ApprovalBroadcaster.clear!(chat)
            AgentGraph::NodeResult.next("commit_memo")
          when "rejected"
            handle_rejection(chat)
          else
            if auto_approve?(state)
              AgentGraph::NodeResult.next(
                "commit_memo",
                updates: { "approval" => "approved" }
              )
            else
              AgentGraph::NodeResult.interrupt(
                updates: { "approval" => "pending" }
              )
            end
          end
        end

        private

        def auto_approve?(state)
          state["auto_approve"] == true
        end

        def handle_rejection(chat)
          AgentGraph::ApprovalBroadcaster.clear!(chat)
          message = create_assistant_message!(chat, REJECTED_MESSAGE)
          ChatUiBroadcaster.message_upsert(message)
          AgentGraph::NodeResult.end(
            updates: {
              "final_answer" => REJECTED_MESSAGE,
              "assistant_message_id" => message.id,
              "approval" => "rejected"
            }
          )
        end

        def create_assistant_message!(chat, content)
          Message.suppressing_turbo_broadcasts do
            chat.messages.create!(role: :assistant, content: content)
          end
        end
      end
    end
  end
end
