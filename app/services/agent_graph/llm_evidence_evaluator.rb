# frozen_string_literal: true

module AgentGraph
  class LlmEvidenceEvaluator
    MAX_TOKENS = 128
    MAX_EVIDENCE_CHARS = 12_000
    SYSTEM_PROMPT = <<~TEXT.squish
      あなたは調査根拠の十分性判定器です。質問に答えず、JSON objectだけを返してください。
      supplied_evidenceだけで質問の主要部分へ具体的かつ根拠に沿って回答できる場合だけsufficientをtrueにしてください。
      根拠に質問と直接関係する情報がない、断片的で結論を支えられない、または重要な最新情報が欠ける場合はfalseです。
      外部知識で不足を補わず、検索語や回答本文も出力しないでください。出力keyはsufficientだけです。
    TEXT

    def initialize(fallback: RoleServices::HeuristicEvidenceEvaluator.new)
      @fallback = fallback
    end

    def call(state:, run:, chat:)
      baseline = @fallback.call(state: state, run: run, chat: chat)
      return heuristic_result(baseline) unless reviewable?(baseline, state)

      model = LlmUsageResolver.model_for("agent.evidence_evaluator")
      return fallback_result(baseline, model, "evidence evaluator model is not configured") unless model

      sufficient, llama_cache, usage = classify(model, state, chat)
      review = sufficient ? baseline : baseline.merge(
        status: "limited",
        reason: "retrieved evidence does not sufficiently support the requested answer"
      )
      [ review, metadata(source: "light", model: model, llama_cache: llama_cache, usage: usage) ]
    rescue StandardError => e
      Rails.logger.warn("AgentGraph::LlmEvidenceEvaluator failed: #{e.class}: #{e.message}")
      fallback_result(baseline || @fallback.call(state: state, run: run, chat: chat), model, e.message)
    end

    private

    def reviewable?(baseline, state)
      baseline.fetch(:status).to_s == "sufficient" &&
        (state["memo_context"].to_s.strip.present? || Array(state["fetched_pages"]).any?)
    end

    def classify(model, state, chat)
      llm = ChatModelCatalog.context_for(model).chat(
        model: model.model_id,
        provider: model.provider.to_sym,
        assume_model_exists: true
      )
      ChatLlmSettings.defaults_for(model: model).apply!(llm)
      ChatLlamaCache.apply!(
        llm,
        chat: chat,
        model: model,
        slot_key: "agent_graph:evidence_evaluator:#{chat.id}:#{model.model_id}"
      )
      llama_cache = llm.instance_variable_get(:@nyoy_llama_cache_metadata) || {}
      configure_llm!(llm)
      llm.with_instructions(SYSTEM_PROMPT)

      usage = {}
      response = llm.ask(evidence_prompt(state)) do |chunk|
        usage.merge!(ChatUsageAttributes.from(chunk))
      end
      usage = ChatUsageAttributes.from(response) if usage.empty?
      [ parse_classification(response.content.to_s), llama_cache.stringify_keys, usage.stringify_keys ]
    end

    def configure_llm!(llm)
      llm.with_temperature(0)
      params = (llm.instance_variable_get(:@params) || {}).dup
      template_kwargs = params.delete(:chat_template_kwargs) || params.delete("chat_template_kwargs") || {}
      llm.with_params(
        **params.symbolize_keys,
        max_tokens: MAX_TOKENS,
        chat_template_kwargs: template_kwargs.to_h.stringify_keys.merge("enable_thinking" => false)
      )
    end

    def evidence_prompt(state)
      payload = {
        question: state.fetch("question").to_s,
        memo_context: state["memo_context"].to_s.presence,
        fetched_pages: Array(state["fetched_pages"]),
        search_results: Array(state["search_results"])
      }
      "supplied_evidence:\n#{JSON.generate(payload)[0, MAX_EVIDENCE_CHARS]}"
    end

    def parse_classification(content)
      json = LlamaJsonParser.repair_truncated(LlamaJsonParser.normalize(content))
      value = json["sufficient"]
      return value if value == true || value == false

      raise ArgumentError, "evidence evaluator sufficient must be boolean"
    end

    def heuristic_result(review)
      [ review, metadata(source: "heuristic", model: nil) ]
    end

    def fallback_result(review, model, error)
      [ review, metadata(source: "heuristic", model: model, fallback: "heuristic", error: error) ]
    end

    def metadata(source:, model:, fallback: nil, error: nil, llama_cache: nil, usage: nil)
      {
        "source" => source,
        "model_id" => model&.model_id,
        "fallback" => fallback,
        "error" => error,
        "llama_cache" => llama_cache.presence,
        "usage" => usage.presence
      }.compact
    end
  end
end
