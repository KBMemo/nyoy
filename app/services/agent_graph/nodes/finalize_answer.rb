# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Publish the approved draft as the final assistant message.
    class FinalizeAnswer
      def call(state:, run:, chat:)
        answer = state["draft"].to_s.presence || state["final_answer"].to_s.presence
        if answer.blank?
          return AgentGraph::NodeResult.fail("missing draft for finalize")
        end

        truncated = state["draft_truncated"] == true
        thinking = state["draft_thinking"].to_s.presence
        message = create_assistant_message!(chat, answer, truncated: truncated, thinking_text: thinking)
        ChatUiBroadcaster.message_upsert(message)
        ChatTruncationBroadcaster.call(chat) if truncated
        AgentGraph::ApprovalBroadcaster.clear!(chat)

        AgentGraph::NodeResult.end(
          updates: {
            "final_answer" => answer,
            "assistant_message_id" => message.id,
            "truncated" => truncated
          }
        )
      end

      private

      def create_assistant_message!(chat, answer, truncated: false, thinking_text: nil)
        Message.suppressing_turbo_broadcasts do
          chat.messages.create!(
            role: :assistant,
            content: answer,
            truncated: truncated,
            thinking_text: thinking_text
          )
        end
      end
    end
  end
end
