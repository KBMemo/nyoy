# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Human-in-the-loop gate for sensitive plans. Resume reads approval.
    class AwaitApproval
      REJECTED_MESSAGE = "調査ドラフトは却下されました。必要なら質問を言い直してください。"

      def call(state:, run:, chat:)
        case state["approval"].to_s
        when "approved", "not_required"
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
          if AgentGraph::ResearchRouting.needs_human_approval?(state)
            AgentGraph::NodeResult.interrupt(
              updates: {
                "approval" => "pending"
              }
            )
          else
            # Safety net: non-sensitive / auto_approve should skip HITL.
            AgentGraph::NodeResult.next(
              "finalize_answer",
              updates: {
                "approval" => AgentGraph::ResearchRouting.auto_approve?(state) ? "approved" : "not_required"
              }
            )
          end
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
