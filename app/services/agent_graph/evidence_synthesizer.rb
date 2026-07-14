# frozen_string_literal: true

module AgentGraph
  # Shared draft / answer synthesis from Research Graph evidence.
  # Used by SynthesizeDraft (and tests that stub LLM).
  #
  # Prefer AppSetting.research_draft_model (light) when set; on failure fall back
  # to the chat model and/or the evidence-pack template per AppSetting.
  class EvidenceSynthesizer
    # Test hook: skip LLM and use the evidence-pack template.
    class << self
      attr_accessor :force_template
    end

    SYNTHESIS_SYSTEM = <<~TEXT.squish
      あなたは調査アシスタントです。与えられたメモ抜粋・検索結果・取得ページだけを根拠に日本語で簡潔に答えてください。
      根拠が無い場合はその旨を明記してください。推測で日付や事実を補わないでください。
      Web 根拠がある場合は簡潔に出典 URL を添えてください。
      却下された前回ドラフトがある場合は、その内容をそのまま繰り返さず、構成・着眼点・根拠の出し方を変えて書き直してください。
    TEXT

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
      return [ sanitize_text(llm_answer), truncated, meta ] if llm_answer.present?

      [
        fallback_answer(evidence),
        false,
        { "source" => "template", "model_id" => nil }
      ]
    end

    def evidence_pack(state)
      {
        question: state.fetch("question").to_s,
        memo: state["memo_context"].to_s.presence,
        search_results: Array(state["search_results"]),
        fetched_pages: Array(state["fetched_pages"]),
        errors: Array(state["errors"]),
        rejection_notes: Array(state["rejection_notes"]),
        replan_count: state["replan_count"].to_i,
        revision_hints: Array(state.dig("plan", "revision_hints"))
      }
    end

    private

    def synthesize_with_fallback(evidence)
      candidates(evidence_models).each do |model, source|
        answer, truncated = ask_model(model, evidence)
        next if answer.blank?

        return [ answer, truncated, { "source" => source, "model_id" => model.model_id } ]
      end

      [ nil, false, { "source" => nil, "model_id" => nil } ]
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
      return [ nil, false ] unless model

      llm_context = ChatModelCatalog.context_for(model)
      llm = llm_context.chat(
        model: model.model_id,
        provider: model.provider.to_sym,
        assume_model_exists: true
      )
      # Use the synthesis model's connection defaults — not the chat's creative overrides.
      ChatLlmSettings.defaults_for(model: model).apply!(llm)

      llm.with_instructions(SYNTHESIS_SYSTEM)
      response = llm.ask(user_prompt(evidence))
      answer = response.content.to_s.strip.presence
      [ sanitize_text(answer), length_truncated_response?(response) ]
    rescue StandardError => e
      Rails.logger.warn(
        "AgentGraph::EvidenceSynthesizer LLM failed model=#{model&.model_id}: #{e.class}: #{e.message}"
      )
      [ nil, false ]
    end

    def sanitize_text(text)
      return text if text.blank?

      text.to_s.delete("\u0000")
    end

    def user_prompt(evidence)
      lines = []
      lines << "質問:\n#{evidence[:question]}\n"
      append_revision_section!(lines, evidence)

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

    def append_revision_section!(lines, evidence)
      notes = evidence[:rejection_notes]
      hints = evidence[:revision_hints]
      return if notes.blank? && hints.blank?

      lines << "書き直し指示（前回ドラフトは却下済み）:"
      lines << "- 再計画回数: #{evidence[:replan_count]}" if evidence[:replan_count].positive?
      hints.each { |hint| lines << "- hint: #{hint}" }
      notes.last(3).each do |note|
        preview = note.is_a?(Hash) ? note["draft_preview"] : note.to_s
        next if preview.blank?

        lines << "- 却下ドラフト#{note.is_a?(Hash) ? note['replan_index'] : ''}: #{preview}"
      end
      lines << "- 前回と同じ言い回し・同じ並びの根拠提示を避け、別の構成で答えてください。"
      lines << ""
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
      if evidence[:replan_count].positive? || evidence[:rejection_notes].any?
        lines << ""
        lines << "**書き直し**（却下 #{evidence[:rejection_notes].size} 回目を踏まえた再構成）"
      end
      lines << ""
      lines << "**質問**"
      lines << evidence[:question]
      lines << ""

      if evidence[:rejection_notes].any?
        lines << "**前回ドラフトで避けた点**"
        evidence[:rejection_notes].last(2).each do |note|
          preview = note.is_a?(Hash) ? note["draft_preview"] : note.to_s
          lines << "- （却下）#{preview.to_s.truncate(160)}" if preview.present?
        end
        Array(evidence[:revision_hints]).each { |hint| lines << "- #{hint}" }
        lines << ""
      end

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
  end
end
