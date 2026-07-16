# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Legacy / safety gate. New Research runs skip this node (see ResearchRouting).
    # Resume still handles approved / rejected for leftover awaiting_approval runs.
    class AwaitApproval
      REJECTED_MESSAGE = "調査ドラフトは却下されました。必要なら質問を言い直してください。"
      MAX_REPLANS = 2

      def call(state:, run:, chat:)
        case state["approval"].to_s
        when "approved", "not_required"
          AgentGraph::ApprovalBroadcaster.clear!(chat)
          AgentGraph::NodeResult.next("finalize_answer")
        when "rejected"
          handle_rejection(state, chat)
        else
          if AgentGraph::ResearchRouting.needs_human_approval?(state)
            AgentGraph::NodeResult.interrupt(
              updates: {
                "approval" => "pending"
              }
            )
          else
            # New research path never requires HITL; finalize immediately.
            AgentGraph::NodeResult.next(
              "finalize_answer",
              updates: {
                "approval" => "not_required"
              }
            )
          end
        end
      end

      private

      def handle_rejection(state, chat)
        AgentGraph::ApprovalBroadcaster.clear!(chat)
        replan_count = state["replan_count"].to_i

        if replan_count < MAX_REPLANS
          return AgentGraph::NodeResult.next(
            "plan_research",
            updates: replan_updates(state, replan_count)
          )
        end

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

      def replan_updates(state, replan_count)
        notes = Array(state["rejection_notes"]) + [ {
          "replan_index" => replan_count + 1,
          "draft_preview" => state["draft"].to_s.truncate(300)
        } ]

        {
          "approval" => nil,
          "draft" => nil,
          "draft_truncated" => false,
          "final_answer" => nil,
          "replan_count" => replan_count + 1,
          "rejection_notes" => notes,
          # Force a fresh plan; keep gathered evidence and budget counters.
          "plan" => {}
        }
      end

      def create_assistant_message!(chat, content)
        Message.suppressing_turbo_broadcasts do
          chat.messages.create!(role: :assistant, content: content)
        end
      end
    end
  end
end
