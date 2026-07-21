# frozen_string_literal: true

module AgentGraph
  class HybridLlmIntentRouter
    MAX_TOKENS = 128
    SYSTEM_PROMPT = <<~TEXT.squish
      あなたはResearch Graphへの昇格判定器です。質問に答えず、JSON objectだけを返してください。
      外部情報の検索、Webページ確認、出典調査、事実検証が回答に必要ならuse_research_graphをtrueにしてください。
      ソフトウェアのframework、library、APIの仕様・設定・retry・versionに関する質問も、公式文書の確認が必要なのでtrueです。
      通常の会話、挨拶、創作、ユーザー自身の情報だけで答えられる依頼はfalseです。
      出力keyはuse_research_graphだけです。
    TEXT

    def initialize(fallback: RoleServices::DeterministicIntentRouter.new)
      @fallback = fallback
    end

    def call(chat:, message:, text:)
      deterministic = @fallback.call(chat: chat, message: message, text: text)
      return deterministic if deterministic
      return nil if text.to_s.strip.empty? || message&.attachments&.attached?
      return nil if ResearchIntent.negative?(text)

      model = LlmUsageResolver.model_for("agent.intent")
      return nil unless model

      classification, metadata = classify(model, text, chat)
      return nil unless classification.fetch("use_research_graph")

      {
        graph_name: ResearchGraph::NAME,
        intent_decision: {
          match: true,
          reason: "llm_research_escalation",
          hits: [],
          profile: "hybrid_llm"
        }.merge(metadata.symbolize_keys)
      }
    rescue StandardError => e
      Rails.logger.warn("AgentGraph::HybridLlmIntentRouter failed: #{e.class}: #{e.message}")
      nil
    end

    private

    def classify(model, text, chat)
      llm = ChatModelCatalog.context_for(model).chat(
        model: model.model_id,
        provider: model.provider.to_sym,
        assume_model_exists: true
      )
      ChatLlmSettings.defaults_for(model: model).apply!(llm)
      ChatLlamaCache.apply!(llm, chat: chat, model: model, slot_key: "agent_graph:intent:#{chat.id}:#{model.model_id}")
      llama_cache = llm.instance_variable_get(:@nyoy_llama_cache_metadata) || {}
      configure_llm!(llm)
      llm.with_instructions(SYSTEM_PROMPT)

      usage = {}
      response = llm.ask("ユーザー入力:\n#{text}") do |chunk|
        usage.merge!(ChatUsageAttributes.from(chunk))
      end
      usage = ChatUsageAttributes.from(response) if usage.empty?

      [
        parse_classification(response.content.to_s),
        {
          "source" => "light",
          "model_id" => model.model_id,
          "llama_cache" => llama_cache.stringify_keys,
          "usage" => usage.stringify_keys
        }
      ]
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

    def parse_classification(content)
      json = LlamaJsonParser.repair_truncated(LlamaJsonParser.normalize(content))
      value = json["use_research_graph"]
      return { "use_research_graph" => value } if value == true || value == false

      raise ArgumentError, "intent use_research_graph must be boolean"
    end
  end
end
