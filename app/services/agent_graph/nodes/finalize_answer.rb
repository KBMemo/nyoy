# frozen_string_literal: true

module AgentGraph
  module Nodes
    # Finalize: build an assistant message from collected state without
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
        evidence = evidence_pack(state)
        llm_answer, truncated = llm_synthesize(chat, evidence)
        return [ llm_answer, truncated ] if llm_answer.present?

        [ fallback_answer(evidence), false ]
      end

      def evidence_pack(state)
        {
          question: state.fetch("question").to_s,
          memo: state["memo_context"].to_s.presence,
          search_results: Array(state["search_results"]),
          fetched_pages: Array(state["fetched_pages"]),
          errors: Array(state["errors"])
        }
      end

      def llm_synthesize(chat, evidence)
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
          あなたは調査アシスタントです。与えられたメモ抜粋・検索結果・取得ページだけを根拠に日本語で簡潔に答えてください。
          根拠が無い場合はその旨を明記してください。推測で日付や事実を補わないでください。
          Web 根拠がある場合は簡潔に出典 URL を添えてください。
        TEXT

        llm.with_instructions(system)
        response = llm.ask(user_prompt(evidence))
        answer = response.content.to_s.strip.presence
        [ answer, length_truncated_response?(response) ]
      rescue StandardError => e
        Rails.logger.warn("AgentGraph::FinalizeAnswer LLM failed: #{e.class}: #{e.message}")
        [ nil, false ]
      end

      def user_prompt(evidence)
        lines = []
        lines << "質問:\n#{evidence[:question]}\n"
        lines << if evidence[:memo].present?
                   "メモ抜粋:\n#{evidence[:memo]}\n"
                 else
                   "メモ抜粋: （該当なし）\n"
                 end

        if evidence[:search_results].any?
          lines << "検索結果:"
          evidence[:search_results].each do |payload|
            query = payload["query"]
            lines << "- query: #{query}" if query.present?
            Array(payload["results"]).first(5).each do |result|
              next unless result.is_a?(Hash)

              lines << "  - #{result['title']}: #{result['url']}"
              lines << "    #{result['content'].to_s.truncate(200)}" if result["content"].present?
            end
          end
          lines << ""
        else
          lines << "検索結果: （なし）\n"
        end

        if evidence[:fetched_pages].any?
          lines << "取得ページ:"
          evidence[:fetched_pages].each do |page|
            lines << "- #{page['title'].presence || page['url']} (#{page['url']})"
            lines << page["content_preview"].to_s.truncate(1_500)
            lines << ""
          end
        else
          lines << "取得ページ: （なし）\n"
        end

        lines.join("\n")
      end

      def length_truncated_response?(response)
        raw = response.respond_to?(:raw) ? response.raw : nil
        body = raw.respond_to?(:body) ? raw.body : raw
        body = JSON.parse(body) if body.is_a?(String)
        body.is_a?(Hash) && body.dig("choices", 0, "finish_reason").to_s == "length"
      rescue StandardError
        false
      end

      def fallback_answer(evidence)
        lines = []
        lines << "### 調査結果（Research Graph）"
        lines << ""
        lines << "**質問**"
        lines << evidence[:question]
        lines << ""
        if evidence[:memo].present?
          lines << "**関連メモ抜粋**"
          lines << evidence[:memo]
          lines << ""
        end
        if evidence[:search_results].any?
          lines << "**検索結果**"
          evidence[:search_results].each do |payload|
            Array(payload["results"]).first(5).each do |result|
              next unless result.is_a?(Hash)

              lines << "- [#{result['title']}](#{result['url']})"
            end
          end
          lines << ""
        end
        if evidence[:fetched_pages].any?
          lines << "**取得ページ要約**"
          evidence[:fetched_pages].each do |page|
            lines << "- #{page['title'].presence || page['url']}: #{page['content_preview'].to_s.truncate(400)}"
          end
          lines << ""
        end
        if evidence[:memo].blank? && evidence[:search_results].blank? && evidence[:fetched_pages].blank?
          lines << "根拠となるメモ・Web 情報は見つかりませんでした。"
        end
        if evidence[:errors].any?
          lines << "**注意**"
          evidence[:errors].each { |err| lines << "- #{err['node']}: #{err['message']}" }
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
