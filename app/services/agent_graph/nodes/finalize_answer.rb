# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Generate the final LLM answer and publish it. LLM/server failures fail the run
    # so ChatErrorBroadcaster can show a proper error bubble.
    class FinalizeAnswer
      def call(state:, run:, chat:)
        if state["draft"].to_s.blank? && state["final_answer"].to_s.blank?
          return AgentGraph::NodeResult.fail("missing draft for finalize")
        end

        answer, truncated, meta = AgentGraph::RoleServices.fetch(:final_answer).call(
          state: state,
          run: run,
          chat: chat
        )
        meta = (meta || {}).stringify_keys

        if answer.blank? || meta["source"] == "error"
          return AgentGraph::NodeResult.fail(
            failure_message(meta, chat),
            updates: {
              "errors" => Array(state["errors"]) + [ {
                "node" => "finalize_answer",
                "code" => "FINAL_ANSWER_FAILED",
                "message" => meta["error"].presence || "final answer synthesis failed"
              } ],
              "final_synthesis" => meta.merge("source" => "error")
            }
          )
        end

        thinking = meta["thinking"].presence
        message = AgentGraph::AssistantMessagePublisher.call(
          chat,
          content: answer,
          truncated: truncated,
          thinking_text: thinking
        )

        AgentGraph::NodeResult.end(
          updates: {
            "final_answer" => answer,
            "assistant_message_id" => message.id,
            "truncated" => truncated,
            "final_synthesis" => meta
          }
        )
      end

      private

      def failure_message(meta, chat)
        error = meta["error"].to_s
        model_id = meta["model_id"].presence || chat.model_association&.model_id

        if connection_error?(error)
          parts = [ "モデルサーバーに接続できません。LLM サーバーが起動しているか確認してください。" ]
          parts << "モデル: #{model_id}" if model_id.present?
          parts << error if error.present?
          return parts.join("\n")
        end

        return error if error.present?

        "最終回答の生成に失敗しました。"
      end

      def connection_error?(message)
        message.match?(ChatErrorBroadcaster::UNREACHABLE_PATTERN)
      end
    end
  end
end
