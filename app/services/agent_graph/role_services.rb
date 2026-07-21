# frozen_string_literal: true

module AgentGraph
  module RoleServices
    DEFAULT_PROFILES = {
      draft: :evidence_pack,
      evidence_evaluator: :heuristic,
      final_answer: :main,
      intent: :deterministic,
      memo_writer: :deterministic,
      planner: :deterministic,
      vision: :main
    }.freeze

    BUILTIN_PROFILES = {
      draft: {
        evidence_pack: -> { AgentGraph::RoleServices::EvidencePackDraft.new },
        llm: -> { AgentGraph::RoleServices::LlmDraft.new }
      },
      evidence_evaluator: {
        heuristic: -> { AgentGraph::RoleServices::HeuristicEvidenceEvaluator.new },
        llm: -> { AgentGraph::LlmEvidenceEvaluator.new }
      },
      final_answer: {
        main: -> { AgentGraph::RoleServices::FinalAnswer.new },
        light: -> { AgentGraph::RoleServices::LightFinalAnswer.new }
      },
      intent: {
        deterministic: -> { AgentGraph::RoleServices::DeterministicIntentRouter.new },
        hybrid_llm: -> { AgentGraph::HybridLlmIntentRouter.new }
      },
      memo_writer: {
        deterministic: -> { AgentGraph::RoleServices::DeterministicMemoWriter.new }
      },
      planner: {
        deterministic: -> { AgentGraph::RoleServices::DeterministicResearchPlanner.new },
        llm: -> { AgentGraph::LlmResearchPlanner.new }
      },
      vision: {
        main: -> { AgentGraph::RoleServices::Vision.new }
      }
    }.freeze

    class << self
      def register(role, service)
        registry[normalize(role)] = service
      end

      def fetch(role)
        key = normalize(role)
        registry.fetch(key) { service_for_profile(key, profile_for(key)) }
      end

      def register_profile(role, profile, factory = nil, &block)
        callable = block || factory
        raise ArgumentError, "role service profile factory must respond to call" unless callable.respond_to?(:call)

        profile_registry[normalize(role)][normalize(profile)] = callable
      end

      def select_profile(role, profile)
        role_key = normalize(role)
        profile_key = normalize(profile)
        factory_for(role_key, profile_key)
        selected_profiles[role_key] = profile_key
      end

      def profile_for(role)
        key = normalize(role)
        selected_profiles.fetch(key) do
          configured_profile(key) || DEFAULT_PROFILES.fetch(key) { unknown_role!(key) }
        end
      end

      def profile_names(role)
        key = normalize(role)
        profile_registry.fetch(key) { unknown_role!(key) }.keys.freeze
      end

      def active_profile_for(role)
        key = normalize(role)
        registry.key?(key) ? :override : profile_for(key)
      end

      def with(role, service)
        key = normalize(role)
        previous = registry.fetch(key, :__missing__)
        register(key, service)
        yield
      ensure
        if previous == :__missing__
          registry.delete(key)
        else
          registry[key] = previous
        end
      end

      def reset!
        @registry = {}
        @profile_registry = nil
        @selected_profiles = {}
      end

      private

      def registry
        @registry ||= {}
      end

      def profile_registry
        @profile_registry ||= BUILTIN_PROFILES.each_with_object({}) do |(role, profiles), copy|
          copy[role] = profiles.dup
        end
      end

      def selected_profiles
        @selected_profiles ||= {}
      end

      def configured_profile(role)
        AgentGraph::RoleServiceConfiguration.profile_for(role)
      end

      def normalize(role)
        role.to_sym
      end

      def service_for_profile(role, profile)
        factory_for(role, profile).call
      end

      def factory_for(role, profile)
        profiles = profile_registry.fetch(role) { unknown_role!(role) }
        profiles.fetch(profile) do
          raise KeyError, "unknown AgentGraph role service profile: #{role}.#{profile}"
        end
      end

      def unknown_role!(role)
        raise KeyError, "unknown AgentGraph role service: #{role}"
      end
    end

    class FinalAnswer
      def call(state:, run:, chat:)
        AgentGraph::FinalAnswerSynthesizer.new(chat).call(state)
      end
    end

    class LightFinalAnswer
      def initialize(fallback: FinalAnswer.new, synthesizer_class: FinalAnswerSynthesizer)
        @fallback = fallback
        @synthesizer_class = synthesizer_class
      end

      def call(state:, run:, chat:)
        model = LlmUsageResolver.model_for("agent.final_answer")
        return fallback_result(state: state, run: run, chat: chat, error: "final answer model is not configured") unless model

        result = synthesize_light(state: state, chat: chat, model: model)
        answer, = result
        return result if answer.present?

        fallback_result(
          state: state,
          run: run,
          chat: chat,
          error: result.third.to_h["error"],
          model: model
        )
      end

      private

      def synthesize_light(state:, chat:, model:)
        @synthesizer_class.new(
          chat,
          model: model,
          source: "light",
          cache_slot_key: "agent_graph:final_light:#{chat.id}:#{model.model_id}"
        ).call(state)
      rescue StandardError => e
        Rails.logger.warn("AgentGraph::RoleServices::LightFinalAnswer failed: #{e.class}: #{e.message}")
        [ nil, false, { "source" => "error", "error" => e.message, "model_id" => model.model_id } ]
      end

      def fallback_result(state:, run:, chat:, error:, model: nil)
        answer, truncated, metadata = @fallback.call(state: state, run: run, chat: chat)
        metadata = metadata.to_h.stringify_keys.merge(
          "fallback" => "main",
          "fallback_error" => error,
          "light_model_id" => model&.model_id
        ).compact
        [ answer, truncated, metadata ]
      end
    end

    class Vision
      def call(image:, mime_type:, prompt:, state:, run:, chat:)
        analysis = VisionChatService.new.analyze(image: image, mime_type: mime_type, prompt: prompt)
        model_id = LlmUsageResolver.resolve("vision.image_understanding")&.model&.model_id
        [ analysis, { "model_id" => model_id } ]
      end
    end

    class DeterministicMemoWriter
      def call(action:, state:, run:, chat:)
        case action.to_s
        when "create" then create_draft(state)
        when "update" then update_draft(state)
        else raise ArgumentError, "unsupported memo writer action: #{action}"
        end
      end

      private

      def create_draft(state)
        title = state["source_title"].to_s.strip.presence || "無題メモ"
        body = state["source_body"].to_s.strip
        memo_draft = { "action" => "create", "title" => title, "body" => body }
        draft = "### #{title}\n\n#{body}"
        [ memo_draft, draft, { "source" => "deterministic" } ]
      end

      def update_draft(state)
        memo_ref = state["memo_ref"].to_s
        original = state["original_memo"].is_a?(Hash) ? state["original_memo"] : {}
        mode = state.dig("plan", "mode").to_s == "replace" ? "replace" : "append"
        body = state["source_body"].to_s
        title = state["source_title"].to_s.presence
        memo_draft = {
          "action" => "update",
          "mode" => mode,
          "memo_ref" => memo_ref,
          "updated_at" => original["updated_at"].to_s,
          "title" => title,
          "body" => mode == "replace" ? body : nil,
          "append_body" => mode == "append" ? body : nil
        }.compact
        [ memo_draft, format_update_draft(original, memo_draft), { "source" => "deterministic" } ]
      end

      def format_update_draft(original, draft)
        title = original["title"].presence || draft["memo_ref"]
        mode_label = draft["mode"] == "replace" ? "本文を置換" : "本文末尾に追記"
        body = draft["body"].presence || draft["append_body"].presence || "(本文変更なし)"
        [
          "### #{title}",
          "",
          "- 対象: `#{draft["memo_ref"]}`",
          "- 操作: #{mode_label}",
          draft["title"].present? ? "- 新タイトル: #{draft["title"]}" : nil,
          "",
          body
        ].compact.join("\n")
      end
    end

    class EvidencePackDraft
      def call(state:, run:, chat:)
        synthesizer = AgentGraph::EvidenceSynthesizer.new(chat)
        evidence = synthesizer.evidence_pack(state)
        draft = synthesizer.fallback_answer(evidence)
        [
          draft,
          false,
          {
            "source" => "evidence_pack",
            "model_id" => nil,
            "thinking" => nil,
            "evidence" => evidence_counts(evidence)
          }
        ]
      end

      private

      def evidence_counts(evidence)
        {
          "memo" => evidence[:memo].to_s.empty? ? 0 : 1,
          "search_results" => Array(evidence[:search_results]).sum { |payload| Array(payload["results"]).size },
          "fetched_pages" => Array(evidence[:fetched_pages]).size,
          "errors" => Array(evidence[:errors]).size
        }
      end
    end

    class LlmDraft
      def call(state:, run:, chat:)
        AgentGraph::EvidenceSynthesizer.new(chat).call(state)
      end
    end

    class HeuristicEvidenceEvaluator
      MAX_ATTEMPTS = 2

      def call(state:, run:, chat:)
        plan = (state["plan"] || {}).deep_dup
        budget = state["budget"] || {}
        attempts = state.dig("evidence_review", "attempts").to_i
        return limited(plan, "evidence review retry limit reached") if attempts >= MAX_ATTEMPTS

        if needs_initial_search?(state, budget)
          plan["need_web"] = true
          return review(status: "needs_web", reason: "web evidence is required but no search has run", plan: plan)
        end

        if needs_followup_search?(state, budget)
          plan["need_web"] = true
          return review(status: "needs_web", reason: "previous web search returned no fetchable results", plan: plan)
        end

        urls = unfetched_urls(state, budget)
        if urls.any? && fetch_budget_available?(budget)
          plan["fetch_urls"] = urls
          return review(
            status: "needs_fetch",
            reason: "search or user-provided URLs need page fetch",
            plan: plan,
            target_urls: urls
          )
        end

        return review(status: "sufficient", reason: "fetched pages are available", plan: plan) if Array(state["fetched_pages"]).any?
        return review(status: "sufficient", reason: "memo context is available", plan: plan) if state["memo_context"].to_s.strip.present?
        return limited(plan, "available evidence is limited and no additional retrieval is available") if retrieval_attempted?(state, budget)

        review(status: "sufficient", reason: "no external evidence required by plan", plan: plan)
      end

      private

      def needs_initial_search?(state, budget)
        state.dig("plan", "need_web") &&
          Array(state["search_results"]).empty? &&
          Array(state["fetched_pages"]).empty? &&
          search_budget_available?(budget)
      end

      def needs_followup_search?(state, budget)
        state.dig("plan", "need_web") &&
          !remaining_queries(state).empty? &&
          Array(state["fetched_pages"]).empty? &&
          unfetched_urls(state, budget).empty? &&
          search_budget_available?(budget)
      end

      def remaining_queries(state)
        queries = Array(state.dig("plan", "queries")).map(&:to_s).map(&:strip).reject(&:blank?)
        searched = Array(state.dig("plan", "searched_queries")).map(&:to_s)
        queries.reject { |query| searched.include?(query) }
      end

      def unfetched_urls(state, _budget)
        AgentGraph::ResearchRouting.fetch_targets(state)
      end

      def search_budget_available?(budget)
        budget["searches_used"].to_i < budget["max_searches"].to_i
      end

      def fetch_budget_available?(budget)
        budget["fetches_used"].to_i < budget["max_fetches"].to_i
      end

      def retrieval_attempted?(state, budget)
        Array(state["search_results"]).any? ||
          Array(state["errors"]).any? ||
          budget["searches_used"].to_i.positive? ||
          budget["fetches_used"].to_i.positive?
      end

      def limited(plan, reason)
        review(status: "limited", reason: reason, plan: plan)
      end

      def review(status:, reason:, plan:, target_urls: [])
        { status: status, reason: reason, plan: plan, target_urls: target_urls }
      end
    end

    class DeterministicIntentRouter
      def call(chat:, message:, text:)
        normalized = text.to_s.strip
        return nil if normalized.empty? && !message&.attachments&.attached?

        memo_update = AgentGraph::MemoUpdateIntent.decision(normalized)
        return intent(AgentGraph::MemoUpdateGraph::NAME, memo_update) if memo_update[:match]

        memo_write = AgentGraph::MemoWriteIntent.decision(normalized)
        return intent(AgentGraph::MemoWriteGraph::NAME, memo_write) if memo_write[:match]

        image_understanding = AgentGraph::ImageUnderstandingIntent.decision(message)
        return intent(AgentGraph::ImageUnderstandingGraph::NAME, image_understanding) if image_understanding[:match]

        research = AgentGraph::ResearchIntent.decision(normalized)
        return intent(AgentGraph::ResearchGraph::NAME, research) if research[:match]

        nil
      end

      private

      def intent(graph_name, intent_decision)
        {
          graph_name: graph_name,
          intent_decision: intent_decision
        }
      end
    end

    class DeterministicResearchPlanner
      URL_PATTERN = %r{https?://[^\s<>\]]+}i
      SENSITIVE_PATTERN = Regexp.union(
        /保存/,
        /メモに/,
        /徒然/,
        /書き込/,
        /更新して/,
        /公開/,
        /投稿/,
        /送信/,
        /確認してから/,
        /承認してから/,
        /ドラフト(を)?確認/,
        /\bpublish\b/i,
        /\bsave\b/i,
        /update[_ ]?memo/i,
        /create[_ ]?memo/i
      )

      def call(state:, run:, chat:)
        question = state.fetch("question").to_s
        plan = {
          "need_memo" => true,
          "need_web" => web_likely?(question),
          "queries" => AgentGraph::SearchQueryNormalizer.queries_for(question),
          "fetch_urls" => extract_urls(question).first(3),
          "sensitive" => sensitive?(question)
        }
        [ plan, { "source" => "deterministic", "model_id" => nil, "fallback" => nil } ]
      end

      private

      def extract_urls(question)
        question.scan(URL_PATTERN).map { |url| url.sub(/[),.]+$/, "") }.uniq
      end

      def web_likely?(question)
        question.match?(/最新|ニュース|Web|ウェブ|ネット|公式|規格|リリース|調べ|調査|出典|根拠|検索/)
      end

      def sensitive?(question)
        historical_save = question.match?(/保存した|保存済み|保存され(た|ている)/)
        explicit_write = question.match?(/保存して|保存する|保存を/)
        return false if historical_save && !explicit_write

        question.match?(SENSITIVE_PATTERN)
      end
    end
  end
end
