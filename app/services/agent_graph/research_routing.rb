# frozen_string_literal: true

module AgentGraph
  # Shared routing helpers for Research Graph after each evidence-gathering node.
  module ResearchRouting
    module_function

    def after_plan(plan)
      plan = plan || {}
      return "recall_memos" if plan["need_memo"]
      return "search_web" if plan["need_web"]
      return "fetch_urls" if Array(plan["fetch_urls"]).any?

      "synthesize_draft"
    end

    def after_recall(state)
      plan = state["plan"] || {}
      return "search_web" if plan["need_web"]
      return "fetch_urls" if Array(plan["fetch_urls"]).any?

      "synthesize_draft"
    end

    def after_search(state)
      return "fetch_urls" if fetch_targets(state).any?

      "synthesize_draft"
    end

    def fetch_targets(state)
      plan_urls = Array(state.dig("plan", "fetch_urls")).map(&:to_s).map(&:strip).reject(&:blank?)
      return plan_urls if plan_urls.any?

      Array(state["search_results"]).flat_map do |payload|
        Array(payload.is_a?(Hash) ? payload["results"] : nil).filter_map do |result|
          result.is_a?(Hash) ? result["url"].to_s.presence : nil
        end
      end.uniq
    end
  end
end
