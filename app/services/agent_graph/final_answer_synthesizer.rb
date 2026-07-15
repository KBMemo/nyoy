# frozen_string_literal: true

module AgentGraph
  # Post-approval final answer generation for Research Graph.
  # Uses the chat's main model (thinking allowed). Falls back to the approved draft.
  class FinalAnswerSynthesizer
    class << self
      # Test hook: skip LLM and publish the approved draft as-is.
      attr_accessor :force_passthrough
    end

    FINAL_SYSTEM = <<~TEXT.squish
      あなたは調査アシスタントです。承認済みの調査ドラフトと根拠資料だけを使って、
      ユーザーへの最終回答を日本語で書いてください。
      ドラフトの結論を尊重しつつ、読みやすい通常のチャット回答に整えてください。
      根拠にない事実・推測を足さないでください。
      Web 根拠がある場合は文末に URL を 1〜3 個添えてください。
      思考過程のタグは出力せず、読者向けの最終回答だけを書いてください。
    TEXT

    def initialize(chat)
      @chat = chat
      @draft_helper = EvidenceSynthesizer.new(chat)
    end

    # @return [String, Boolean, Hash] answer, truncated?, meta
    def call(state)
      draft = state["draft"].to_s.strip
      evidence = @draft_helper.evidence_pack(state).merge(approved_draft: draft)

      if self.class.force_passthrough || draft.blank?
        return [
          draft.presence || @draft_helper.fallback_answer(evidence),
          state["draft_truncated"] == true,
          { "source" => "draft", "model_id" => nil, "thinking" => nil }
        ]
      end

      answer, truncated, meta = ask_main_model(evidence)
      if answer.blank?
        return [
          draft,
          state["draft_truncated"] == true,
          { "source" => "draft_fallback", "model_id" => nil, "thinking" => nil }
        ]
      end

      composed = compose_answer(answer, evidence)
      [ composed, truncated == true, (meta || {}).stringify_keys ]
    end

    private

    def ask_main_model(evidence)
      model = @chat.model_association
      return [ nil, false, {} ] unless model

      llm_context = ChatModelCatalog.context_for(model)
      llm = llm_context.chat(
        model: model.model_id,
        provider: model.provider.to_sym,
        assume_model_exists: true
      )
      ChatLlmSettings.apply!(llm, chat: @chat)
      llm.with_instructions(FINAL_SYSTEM)
      response = llm.ask(user_prompt(evidence))
      answer, thinking = @draft_helper.extract_answer_and_thinking(response)
      [
        answer,
        @draft_helper.length_truncated_response?(response),
        {
          "source" => "main",
          "model_id" => model.model_id,
          "thinking" => thinking.presence
        }
      ]
    rescue StandardError => e
      Rails.logger.warn(
        "AgentGraph::FinalAnswerSynthesizer LLM failed model=#{model&.model_id}: #{e.class}: #{e.message}"
      )
      [ nil, false, {} ]
    end

    def compose_answer(llm_answer, evidence)
      body = llm_answer.to_s.strip
      appendix = @draft_helper.compact_sources(evidence)

      if body.present? && appendix.present?
        "#{body}\n\n---\n\n#{appendix}"
      else
        body.presence || evidence[:approved_draft].to_s
      end
    end

    def user_prompt(evidence)
      lines = []
      lines << "質問:\n#{evidence[:question]}\n"
      lines << "承認済み調査ドラフト:\n#{evidence[:approved_draft].to_s.truncate(2_000)}\n"

      memo = evidence[:memo].to_s.strip
      lines << if memo.present?
                 "メモ抜粋:\n#{memo.truncate(800)}\n"
               else
                 "メモ抜粋: （該当なし）\n"
               end

      if evidence[:search_results].any?
        lines << "検索結果:"
        evidence[:search_results].each do |payload|
          next unless payload.is_a?(Hash)

          query = payload["query"]
          lines << "- query: #{query}" if query.present?
          Array(payload["results"]).first(5).each do |result|
            next unless result.is_a?(Hash)

            lines << "  - #{result['title']}: #{result['url']}"
            lines << "    #{result['content'].to_s.truncate(120)}" if result["content"].present?
          end
        end
        lines << ""
      end

      if evidence[:fetched_pages].any?
        lines << "取得ページ（要約のみ）:"
        evidence[:fetched_pages].first(3).each do |page|
          next unless page.is_a?(Hash)

          lines << "- #{page['title'].presence || page['url']} (#{page['url']})"
          lines << page["content_preview"].to_s.truncate(400)
          lines << ""
        end
      end

      lines << "出力: 最終回答本文のみ。ドラフトの重複した出典見出しは省略してよい（出典はシステムが付けます）。"
      lines.join("\n")
    end
  end
end
