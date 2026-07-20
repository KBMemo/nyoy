# frozen_string_literal: true

module AgentGraph
  class LlmResearchPlanner
    MAX_TOKENS = 256
    SYSTEM_PROMPT = <<~TEXT.squish
      あなたは調査経路の分類器です。質問に答えず、JSON objectだけを返してください。
      need_webは、最新情報、外部仕様、技術文書、固有のWebページなど、メモ以外の確認が必要ならtrueです。
      need_memoは、ユーザー固有の過去メモが回答に役立つ可能性がある場合だけtrueです。
      queriesはWeb検索またはメモ検索に使える簡潔な文字列を最大3件返してください。
      出力keyはneed_web, need_memo, queriesだけです。
    TEXT

    def initialize(fallback: RoleServices::DeterministicResearchPlanner.new)
      @fallback = fallback
    end

    def call(state:, run:, chat:)
      baseline = fallback_plan(state: state, run: run, chat: chat)
      model = AppSetting.research_planner_model
      return fallback_result(baseline, model, "planner model is not configured") unless model

      plan = merge_classification(baseline, classify(model, state.fetch("question").to_s, chat))
      [ plan, metadata(source: "light", model: model) ]
    rescue StandardError => e
      Rails.logger.warn("AgentGraph::LlmResearchPlanner failed: #{e.class}: #{e.message}")
      fallback_result(baseline || fallback_plan(state: state, run: run, chat: chat), model, e.message)
    end

    private

    def classify(model, question, chat)
      llm = ChatModelCatalog.context_for(model).chat(
        model: model.model_id,
        provider: model.provider.to_sym,
        assume_model_exists: true
      )
      ChatLlmSettings.defaults_for(model: model).apply!(llm)
      ChatLlamaCache.apply!(llm, chat: chat, model: model, slot_key: "agent_graph:planner:#{chat.id}:#{model.model_id}")
      llm.with_temperature(0)
      params = (llm.instance_variable_get(:@params) || {}).dup
      template_kwargs = params.delete(:chat_template_kwargs) || params.delete("chat_template_kwargs") || {}
      llm.with_params(
        **params.symbolize_keys,
        max_tokens: MAX_TOKENS,
        chat_template_kwargs: template_kwargs.to_h.stringify_keys.merge("enable_thinking" => false)
      )
      llm.with_instructions(SYSTEM_PROMPT)

      response = llm.ask("質問:\n#{question}")
      parse_classification(response.content.to_s)
    end

    def parse_classification(content)
      json = LlamaJsonParser.repair_truncated(LlamaJsonParser.normalize(content))
      need_web = strict_boolean(json, "need_web")
      need_memo = strict_boolean(json, "need_memo")
      queries = Array(json["queries"]).map(&:to_s).map(&:strip).reject(&:blank?).uniq.first(3)
      raise ArgumentError, "planner queries are missing" if queries.empty?

      { "need_web" => need_web, "need_memo" => need_memo, "queries" => queries }
    end

    def strict_boolean(json, key)
      value = json[key]
      return value if value == true || value == false

      raise ArgumentError, "planner #{key} must be boolean"
    end

    def merge_classification(baseline, classification)
      baseline.merge(classification)
    end

    def fallback_plan(state:, run:, chat:)
      result = @fallback.call(state: state, run: run, chat: chat)
      result.is_a?(Array) ? result.first : result
    end

    def fallback_result(plan, model, error)
      [ plan, metadata(source: "deterministic", model: model, fallback: "deterministic", error: error) ]
    end

    def metadata(source:, model:, fallback: nil, error: nil)
      {
        "source" => source,
        "model_id" => model&.model_id,
        "fallback" => fallback,
        "error" => error
      }.compact
    end
  end
end
