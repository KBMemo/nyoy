# frozen_string_literal: true

module AgentGraph
  # Final research answer for Research Graph.
  # Uses the chat's main model (thinking allowed). On failure returns no answer so
  # FinalizeAnswer can fail the run and ChatErrorBroadcaster can show an error bubble.
  class FinalAnswerSynthesizer
    class << self
      # Test hook: skip LLM and publish the evidence pack / draft as-is.
      attr_accessor :force_passthrough
    end

    FINAL_SYSTEM = <<~TEXT.squish
      あなたは調査アシスタントです。与えられたメモ抜粋・検索結果・取得ページだけを根拠に、
      ユーザーへの最終回答を日本語で書いてください。
      確認用ドラフトや箇条書きだけの要約ではなく、通常のチャット応答として読んで分かる文章にしてください。
      結論を先に書き、必要なら手順や選択肢を補足してください。
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
      evidence = @draft_helper.evidence_pack(state)

      if self.class.force_passthrough
        draft = state["draft"].to_s.strip
        return [
          draft.presence || @draft_helper.fallback_answer(evidence),
          state["draft_truncated"] == true,
          { "source" => "draft", "model_id" => nil, "thinking" => nil }
        ]
      end

      answer, truncated, meta = ask_main_model(evidence)
      if answer.blank?
        return [
          nil,
          false,
          (meta || {}).stringify_keys.merge("source" => "error")
        ]
      end

      composed = compose_answer(answer, evidence)
      [ composed, truncated == true, (meta || {}).stringify_keys ]
    end

    private

    def ask_main_model(evidence)
      model = @chat.model_association
      return [ nil, false, { "error" => "no chat model" } ] unless model

      llm_context = ChatModelCatalog.context_for(model)
      llm = llm_context.chat(
        model: model.model_id,
        provider: model.provider.to_sym,
        assume_model_exists: true
      )
      ChatLlmSettings.apply!(llm, chat: @chat)
      llm.with_instructions(FINAL_SYSTEM)

      progress = ThinkingProgress.new(@chat)
      streamed_thinking = +""
      streamed_content = +""

      response = llm.ask(user_prompt(evidence)) do |chunk|
        thinking_delta = chunk.thinking&.text
        streamed_thinking << thinking_delta if thinking_delta.is_a?(String) && !thinking_delta.empty?

        content_delta = chunk.content
        streamed_content << content_delta if content_delta.is_a?(String) && !content_delta.empty?

        live = live_thinking_text(streamed_thinking, streamed_content)
        progress.push(live) if live.present?
      end

      answer, thinking = @draft_helper.extract_answer_and_thinking(response)
      thinking = thinking.presence || live_thinking_text(streamed_thinking, streamed_content).presence
      progress.flush(thinking) if thinking.present?

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
      [ nil, false, { "error" => "#{e.class}: #{e.message}", "model_id" => model&.model_id } ]
    end

    def live_thinking_text(streamed_thinking, streamed_content)
      return streamed_thinking if streamed_thinking.present?

      _content, embedded = @draft_helper.peel_think_blocks(streamed_content)
      embedded.map { |part| part.to_s.strip }.reject(&:blank?).join("\n\n")
    end

    def compose_answer(llm_answer, evidence)
      body = llm_answer.to_s.strip
      appendix = @draft_helper.compact_sources(evidence)

      if body.present? && appendix.present?
        "#{body}\n\n---\n\n#{appendix}"
      else
        body
      end
    end

    def user_prompt(evidence)
      lines = []
      lines << "質問:\n#{evidence[:question]}\n"

      memo = evidence[:memo].to_s.strip
      lines << if memo.present?
                 "メモ抜粋:\n#{memo.truncate(500)}\n"
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
            lines << "    #{result['content'].to_s.truncate(100)}" if result["content"].present?
          end
        end
        lines << ""
      end

      if evidence[:fetched_pages].any?
        lines << "取得ページ（要約のみ）:"
        evidence[:fetched_pages].first(3).each do |page|
          next unless page.is_a?(Hash)

          lines << "- #{page['title'].presence || page['url']} (#{page['url']})"
          lines << page["content_preview"].to_s.truncate(350)
          lines << ""
        end
      end

      lines << "出力: 最終回答本文のみ（出典リストはシステムが付けます）。"
      lines.join("\n")
    end
  end
end
