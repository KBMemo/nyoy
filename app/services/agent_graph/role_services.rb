# frozen_string_literal: true

module AgentGraph
  module RoleServices
    DEFAULTS = {
      draft: -> { AgentGraph::RoleServices::EvidencePackDraft.new },
      evidence_evaluator: -> { AgentGraph::RoleServices::HeuristicEvidenceEvaluator.new },
      final_answer: -> { AgentGraph::RoleServices::FinalAnswer.new },
      intent: -> { AgentGraph::RoleServices::DeterministicIntentRouter.new }
    }.freeze

    class << self
      def register(role, service)
        registry[normalize(role)] = service
      end

      def fetch(role)
        key = normalize(role)
        registry.fetch(key) { default_for(key) }
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
      end

      private

      def registry
        @registry ||= {}
      end

      def normalize(role)
        role.to_sym
      end

      def default_for(role)
        factory = DEFAULTS.fetch(role) do
          raise KeyError, "unknown AgentGraph role service: #{role}"
        end
        factory.call
      end
    end

    class FinalAnswer
      def call(state:, run:, chat:)
        AgentGraph::FinalAnswerSynthesizer.new(chat).call(state)
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
  end
end
