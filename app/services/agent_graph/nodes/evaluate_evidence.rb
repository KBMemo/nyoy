# frozen_string_literal: true

module AgentGraph
  module Nodes
    class EvaluateEvidence
      MAX_ATTEMPTS = 2

      def call(state:, run:, chat:)
        review = review_for(state)
        AgentGraph::NodeResult.next(updates: {
          "plan" => review.fetch(:plan),
          "evidence_review" => {
            "status" => review.fetch(:status),
            "reason" => review.fetch(:reason),
            "attempts" => next_attempt(state)
          }
        })
      end

      private

      def review_for(state)
        plan = (state["plan"] || {}).deep_dup
        budget = state["budget"] || {}
        attempts = state.dig("evidence_review", "attempts").to_i
        return limited(plan, "evidence review retry limit reached") if attempts >= MAX_ATTEMPTS

        if needs_initial_search?(state, budget)
          plan["need_web"] = true
          return review(status: "needs_web", reason: "web evidence is required but no search has run", plan: plan)
        end

        urls = unfetched_urls(state, budget)
        if urls.any? && fetch_budget_available?(budget)
          plan["fetch_urls"] = urls
          return review(status: "needs_fetch", reason: "search or user-provided URLs need page fetch", plan: plan)
        end

        return review(status: "sufficient", reason: "fetched pages are available", plan: plan) if Array(state["fetched_pages"]).any?
        return review(status: "sufficient", reason: "memo context is available", plan: plan) if state["memo_context"].to_s.strip.present?
        return limited(plan, "available evidence is limited and no additional retrieval is available") if retrieval_attempted?(state, budget)

        review(status: "sufficient", reason: "no external evidence required by plan", plan: plan)
      end

      def needs_initial_search?(state, budget)
        state.dig("plan", "need_web") &&
          Array(state["search_results"]).empty? &&
          search_budget_available?(budget)
      end

      def unfetched_urls(state, budget)
        attempted = Array(budget["fetched_urls"]).map(&:to_s)
        AgentGraph::ResearchRouting.fetch_targets(state)
          .map(&:to_s)
          .map(&:strip)
          .reject(&:blank?)
          .reject { |url| attempted.include?(url) }
          .uniq
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

      def review(status:, reason:, plan:)
        { status: status, reason: reason, plan: plan }
      end

      def next_attempt(state)
        state.dig("evidence_review", "attempts").to_i + 1
      end
    end
  end
end
