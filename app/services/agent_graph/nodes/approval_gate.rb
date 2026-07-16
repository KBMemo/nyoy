# frozen_string_literal: true

module AgentGraph
  module Nodes
    class ApprovalGate
      def initialize(approved_goto:, rejected_message:)
        @approved_goto = approved_goto
        @rejected_message = rejected_message
      end

      def call(state:, run:, chat:)
        case state["approval"].to_s
        when "approved", "not_required"
          AgentGraph::NodeResult.next(@approved_goto)
        when "rejected"
          handle_rejection(chat)
        else
          if state["auto_approve"] == true
            AgentGraph::NodeResult.next(
              @approved_goto,
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

      def handle_rejection(chat)
        message = AgentGraph::AssistantMessagePublisher.call(
          chat,
          content: @rejected_message
        )
        AgentGraph::NodeResult.end(
          updates: {
            "final_answer" => @rejected_message,
            "assistant_message_id" => message.id,
            "approval" => "rejected"
          }
        )
      end
    end
  end
end
