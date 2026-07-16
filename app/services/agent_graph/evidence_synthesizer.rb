# frozen_string_literal: true

module AgentGraph
  # Shared draft / evidence helpers for Research Graph.
  # Used by SynthesizeDraft; FinalAnswerSynthesizer reuses evidence_pack and shared helpers.
  #
  # Prefer AppSetting.research_draft_model (light) when set; on failure fall back
  # to the chat model and/or the evidence-pack template per AppSetting.
  class EvidenceSynthesizer
    # Test hook: skip LLM and use the evidence-pack template.
    class << self
      attr_accessor :force_template
    end

    SYNTHESIS_SYSTEM = <<~TEXT.squish
      あなたは調査アシスタントです。与えられたメモ抜粋・検索結果・取得ページだけを根拠に日本語で答えてください。
      回答は短く：結論を先に、必要なら箇条書き最大 5 項目まで。長い前置き・重複説明・ページ全文の再掲は禁止です。
      根拠が無い場合のみその旨を一文で書いてください。推測で日付や事実を補わないでください。
      Web 根拠がある場合は文末に URL を 1〜3 個添えるだけで十分です（詳細な出典リストはシステムが付けます）。
      思考過程のタグは出力せず、読者向けの最終回答だけを書いてください。
    TEXT

    THINK_BLOCK = %r{
      <think\b[^>]*>.*?</think>
      | <redacted_reasoning\b[^>]*>.*?</redacted_reasoning>
      | <\|thinking\|>.*?<\|/thinking\|>
    }mix

    def initialize(chat)
      @chat = chat
    end

    # @return [String, Boolean, Hash] draft, truncated?, meta (source / model_id)
    def call(state)
      evidence = evidence_pack(state)
      if self.class.force_template
        return [
          fallback_answer(evidence),
          false,
          { "source" => "template", "model_id" => nil }
        ]
      end

      llm_answer, truncated, meta = synthesize_with_fallback(evidence)
      draft = compose_draft(llm_answer, evidence)
      used = if llm_answer.present?
               (meta || {}).merge("source" => meta&.dig("source") || "main")
             else
               { "source" => "template", "model_id" => nil, "thinking" => nil }
             end

      [ draft, truncated == true, used.stringify_keys ]
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

    private

    def synthesize_with_fallback(evidence)
      candidates(evidence_models).each do |model, source|
        answer, thinking, truncated = ask_model(model, evidence)
        next if answer.blank?

        return [
          answer,
          truncated,
          {
            "source" => source,
            "model_id" => model.model_id,
            "thinking" => thinking.presence
          }
        ]
      end

      [ nil, false, { "source" => nil, "model_id" => nil, "thinking" => nil } ]
    end

    def evidence_models
      main = @chat.model_association
      light = AppSetting.research_draft_model
      [ light, main ]
    end

    # Ordered unique (model, source) pairs for LLM attempts.
    def candidates(light_and_main)
      light, main = light_and_main
      list = []

      if light
        list << [ light, "light" ]
      elsif main
        list << [ main, "main" ]
      end

      if light && AppSetting.research_draft_fallback == "main" && main && main.id != light.id
        list << [ main, "main" ]
      end

      list
    end

    def ask_model(model, evidence)
      return [ nil, nil, false ] unless model

      llm_context = ChatModelCatalog.context_for(model)
      llm = llm_context.chat(
        model: model.model_id,
        provider: model.provider.to_sym,
        assume_model_exists: true
      )
      if model.id == @chat.model_association&.id
        ChatLlmSettings.apply!(llm, chat: @chat)
      else
        ChatLlmSettings.defaults_for(model: model).apply!(llm)
      end
      # Draft synthesis prioritizes latency: skip thinking tokens (qwen / llama.cpp).
      disable_thinking!(llm)

      llm.with_instructions(SYNTHESIS_SYSTEM)
      response = llm.ask(user_prompt(evidence))
      answer, thinking = extract_answer_and_thinking(response)
      [ answer, thinking, length_truncated_response?(response) ]
    rescue StandardError => e
      Rails.logger.warn(
        "AgentGraph::EvidenceSynthesizer LLM failed model=#{model&.model_id}: #{e.class}: #{e.message}"
      )
      [ nil, nil, false ]
    end

    def disable_thinking!(llm)
      existing = (llm.instance_variable_get(:@params) || {}).dup
      kwargs = existing[:chat_template_kwargs] || existing["chat_template_kwargs"] || {}
      kwargs = kwargs.to_h.stringify_keys.merge("enable_thinking" => false)
      llm.with_params(**existing.symbolize_keys, chat_template_kwargs: kwargs)
    end

    # Prefer content as the draft body; keep thinking for the UI 「思考」 panel.
    def extract_answer_and_thinking(response)
      field_thinking =
        if response.respond_to?(:thinking)
          response.thinking&.text.to_s
        else
          ""
        end
      content, embedded = peel_think_blocks(response.content.to_s)
      thinking = sanitize_text(
        [ field_thinking, *embedded ].map { |part| part.to_s.strip }.reject(&:blank?).join("\n\n")
      )
      answer = sanitize_text(content).presence || thinking.presence
      [ answer, thinking.presence ]
    end

    def peel_think_blocks(text)
      embedded = []
      cleaned = text.to_s.gsub(THINK_BLOCK) do |match|
        embedded << unwrap_think_block(match)
        ""
      end
      [ cleaned.strip, embedded.reject(&:blank?) ]
    end

    def unwrap_think_block(match)
      match.to_s
        .sub(/\A<think\b[^>]*>/i, "")
        .sub(%r{</think>\s*\z}i, "")
        .sub(/\A<redacted_reasoning\b[^>]*>/i, "")
        .sub(%r{</redacted_reasoning>\s*\z}i, "")
        .sub(/\A<\|thinking\|>/i, "")
        .sub(%r{<\|/thinking\|>\s*\z}i, "")
        .strip
    end

    def strip_think_blocks(text)
      peel_think_blocks(text).first
    end

    def sanitize_text(text)
      return text if text.blank?

      text.to_s.delete("\u0000")
    end

    # Short answer + compact source list. Tool traces already show full search/fetch payloads.
    def compose_draft(llm_answer, evidence)
      body = llm_answer.to_s.strip
      appendix = compact_sources(evidence)

      if body.present? && appendix.present?
        "#{body}\n\n---\n\n#{appendix}"
      elsif body.present?
        body
      else
        fallback_answer(evidence)
      end
    end

    def compact_sources(evidence)
      lines = []
      lines << "### 出典"

      memo = evidence[:memo].to_s.strip
      if memo.present?
        lines << ""
        lines << "**関連メモ**"
        lines << memo.truncate(280)
      end

      links = []
      Array(evidence[:search_results]).each do |payload|
        next unless payload.is_a?(Hash)

        results = Array(payload["results"]).select { |result| result.is_a?(Hash) && result["url"].present? }
        if results.any?
          results.first(5).each do |result|
            links << "- [#{result['title'].presence || result['url']}](#{result['url']})"
          end
        else
          query = payload["query"].presence || "（クエリ不明）"
          warning = payload["warning"].presence || "結果なし"
          lines << "" if lines.size == 1
          lines << "- 検索「#{query}」: #{warning}"
        end
      end

      Array(evidence[:fetched_pages]).first(3).each do |page|
        next unless page.is_a?(Hash)

        url = page["url"].presence
        next if url.blank?

        title = page["title"].presence || url
        links << "- [#{title}](#{url})"
      end

      if links.any?
        lines << ""
        lines << "**検索・取得**"
        lines.concat(links.uniq.first(8))
      end

      return "" if lines.size <= 1

      lines.join("\n")
    end

    def user_prompt(evidence)
      lines = []
      lines << "質問:\n#{evidence[:question]}\n"

      memo = evidence[:memo].to_s.strip
      lines << if memo.present?
                 "メモ抜粋:\n#{memo.truncate(800)}\n"
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
            lines << "    #{result['content'].to_s.truncate(120)}" if result["content"].present?
          end
        end
        lines << ""
      else
        lines << "検索結果: （なし）\n"
      end

      if evidence[:fetched_pages].any?
        lines << "取得ページ（要約のみ。長文を再掲しない）:"
        evidence[:fetched_pages].first(3).each do |page|
          lines << "- #{page['title'].presence || page['url']} (#{page['url']})"
          lines << page["content_preview"].to_s.truncate(400)
          lines << ""
        end
      else
        lines << "取得ページ: （なし）\n"
      end

      lines << "出力形式: 短い結論＋必要なら箇条書き（合計おおよそ 400 文字以内）。"
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
      lines << "### 調査結果"
      lines << ""
      lines << "**質問**"
      lines << evidence[:question]
      lines << ""

      sources = compact_sources(evidence)
      if sources.present?
        lines << sources
      else
        lines << "根拠となるメモ・Web 情報は見つかりませんでした。"
      end

      if evidence[:errors].any?
        lines << ""
        lines << "**注意**"
        evidence[:errors].first(3).each { |err| lines << "- #{err['node']}: #{err['message'].to_s.truncate(120)}" }
      end
      lines.join("\n")
    end

    public :compact_sources, :fallback_answer, :extract_answer_and_thinking,
           :length_truncated_response?, :peel_think_blocks
  end
end
