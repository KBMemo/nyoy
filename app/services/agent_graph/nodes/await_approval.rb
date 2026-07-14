# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Human-in-the-loop gate. First visit interrupts; resume reads approval.
    class AwaitApproval
      REJECTED_MESSAGE = "調査ドラフトは却下されました。必要なら質問を言い直してください。"

      def call(state:, run:, chat:)
        case state["approval"].to_s
        when "approved"
          AgentGraph::ApprovalBroadcaster.clear!(chat)
          AgentGraph::NodeResult.next("finalize_answer")
        when "rejected"
          message = create_assistant_message!(chat, REJECTED_MESSAGE)
          ChatUiBroadcaster.message_upsert(message)
          AgentGraph::ApprovalBroadcaster.clear!(chat)
          AgentGraph::NodeResult.end(
            updates: {
              "final_answer" => REJECTED_MESSAGE,
              "assistant_message_id" => message.id
            }
          )
        else
          AgentGraph::NodeResult.interrupt(
            updates: {
              "approval" => "pending"
            }
          )
        end
      end

      private

      def create_assistant_message!(chat, content)
        Message.suppressing_turbo_broadcasts do
          chat.messages.create!(role: :assistant, content: content)
        end
      end
    end
  end
end
