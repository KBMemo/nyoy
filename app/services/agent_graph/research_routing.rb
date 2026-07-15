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

    def after_synthesize(state)
      return "await_approval" if needs_human_approval?(state)

      "finalize_answer"
    end

    # Chat UI always shows the draft approval panel unless MCP/auto_approve.
    # plan.sensitive remains for labeling / future policy, but no longer gates HITL.
    def needs_human_approval?(state)
      !auto_approve?(state)
    end

    def sensitive_plan?(state)
      value = state.dig("plan", "sensitive")
      value == true || value.to_s == "true"
    end

    def auto_approve?(state)
      value = state["auto_approve"]
      value == true || value.to_s == "true"
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
