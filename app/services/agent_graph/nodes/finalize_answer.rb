# frozen_string_literal: true

module AgentGraph
  module Nodes
    # R0 finalize: build an assistant message from collected state without
    # streaming tool-loop. Uses chat model when available; falls back to a
    # deterministic draft so the graph always terminates with a bubble.
    class FinalizeAnswer
      def call(state:, run:, chat:)
        answer, truncated = synthesize(state, chat)
        message = create_assistant_message!(chat, answer, truncated: truncated)
        ChatUiBroadcaster.message_upsert(message)
        ChatTruncationBroadcaster.call(chat) if truncated

        AgentGraph::NodeResult.end(
          updates: {
            "final_answer" => answer,
            "assistant_message_id" => message.id,
            "truncated" => truncated
          }
        )
      end

      private

      def synthesize(state, chat)
        question = state.fetch("question").to_s
        memo = state["memo_context"].to_s.presence
        errors = Array(state["errors"])

        llm_answer, truncated = llm_synthesize(chat, question, memo)
        return [ llm_answer, truncated ] if llm_answer.present?

        [ fallback_answer(question, memo, errors), false ]
      end

      def llm_synthesize(chat, question, memo)
        model = chat.model_association
        return [ nil, false ] unless model

        llm_context = ChatModelCatalog.context_for(model)
        llm = llm_context.chat(
          model: model.model_id,
          provider: model.provider.to_sym,
          assume_model_exists: true
        )
        ChatLlmSettings.apply!(llm, chat: chat)

        system = <<~TEXT.squish
          あなたは調査アシスタントです。与えられたメモ抜粋だけを根拠に日本語で簡潔に答えてください。
          根拠が無い場合はその旨を明記してください。推測で日付や事実を補わないでください。
        TEXT

        user = +"質問:\n#{question}\n\n"
        user << if memo.present?
                  "メモ抜粋:\n#{memo}"
                else
                  "メモ抜粋: （該当なし）"
                end

        llm.with_instructions(system)
        response = llm.ask(user)
        answer = response.content.to_s.strip.presence
        [ answer, length_truncated_response?(response) ]
      rescue StandardError => e
        Rails.logger.warn("AgentGraph::FinalizeAnswer LLM failed: #{e.class}: #{e.message}")
        [ nil, false ]
      end

      def length_truncated_response?(response)
        raw = response.respond_to?(:raw) ? response.raw : nil
        body = raw.respond_to?(:body) ? raw.body : raw
        body = JSON.parse(body) if body.is_a?(String)
        body.is_a?(Hash) && body.dig("choices", 0, "finish_reason").to_s == "length"
      rescue StandardError
        false
      end

      def fallback_answer(question, memo, errors)
        lines = []
        lines << "### 調査結果（Research Graph R0）"
        lines << ""
        lines << "**質問**"
        lines << question
        lines << ""
        if memo.present?
          lines << "**関連メモ抜粋**"
          lines << memo
        else
          lines << "関連するメモは見つかりませんでした。Web 検索ノードは R1 以降で追加予定です。"
        end
        if errors.any?
          lines << ""
          lines << "**注意**"
          errors.each { |err| lines << "- #{err['node']}: #{err['message']}" }
        end
        lines.join("\n")
      end

      def create_assistant_message!(chat, answer, truncated: false)
        Message.suppressing_turbo_broadcasts do
          chat.messages.create!(role: :assistant, content: answer, truncated: truncated)
        end
      end
    end
  end
end
