# frozen_string_literal: true

module AgentGraph
  module Nodes
    # After draft approval (or auto_approve), generate a final LLM answer and publish it.
    class FinalizeAnswer
      def call(state:, run:, chat:)
        if state["draft"].to_s.blank? && state["final_answer"].to_s.blank?
          return AgentGraph::NodeResult.fail("missing draft for finalize")
        end

        answer, truncated, meta = AgentGraph::FinalAnswerSynthesizer.new(chat).call(state)
        if answer.blank?
          return AgentGraph::NodeResult.fail(
            "empty final answer",
            updates: {
              "errors" => Array(state["errors"]) + [ {
                "node" => "finalize_answer",
                "code" => "EMPTY_FINAL_ANSWER",
                "message" => "final answer synthesis produced no content"
              } ]
            }
          )
        end

        thinking = meta.is_a?(Hash) ? meta["thinking"].presence : nil
        message = create_assistant_message!(chat, answer, truncated: truncated, thinking_text: thinking)
        ChatUiBroadcaster.message_upsert(message)
        ChatTruncationBroadcaster.call(chat) if truncated
        AgentGraph::ApprovalBroadcaster.clear!(chat)

        AgentGraph::NodeResult.end(
          updates: {
            "final_answer" => answer,
            "assistant_message_id" => message.id,
            "truncated" => truncated,
            "final_synthesis" => (meta || {}).stringify_keys
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
