# frozen_string_literal: true

module AgentGraph
  module Nodes
    class SearchWeb
      MAX_QUERIES = 2
      MAX_URLS_TO_QUEUE = 3

      def call(state:, run:, chat:)
        plan = state.fetch("plan", {})
        unless plan["need_web"]
          return AgentGraph::NodeResult.next(AgentGraph::ResearchRouting.after_search(state))
        end

        budget = ChatTools::WebToolBudget.from_graph_budget(state["budget"])
        tool = ChatTools::WebSearch.new(budget: budget)
        queries = Array(plan["queries"]).map(&:to_s).map(&:strip).reject(&:blank?).first(MAX_QUERIES)
        queries = [ state.fetch("question").to_s ] if queries.empty?

        search_results = Array(state["search_results"]).dup
        errors = Array(state["errors"]).dup

        queries.each do |query|
          payload = tool.execute(q: query)
          AgentGraph::ToolTraceRecorder.record!(
            chat,
            name: "web_search",
            arguments: { "q" => query },
            result: payload
          )
          if payload.is_a?(String)
            errors << {
              "node" => "search_web",
              "code" => "SEARCH_FAILED",
              "message" => payload.to_s.truncate(300),
              "query" => query
            }
            next
          end

          search_results << payload.merge("query" => query)
        end

        queued_urls = queue_urls_from_results(plan, search_results)
        next_plan = plan.merge("fetch_urls" => queued_urls)

        AgentGraph::NodeResult.next(
          AgentGraph::ResearchRouting.after_search(state.merge("plan" => next_plan, "search_results" => search_results)),
          updates: {
            "plan" => next_plan,
            "search_results" => search_results,
            "budget" => budget.to_graph_budget,
            "errors" => errors
          }
        )
      end

      private

      def queue_urls_from_results(plan, search_results)
        existing = Array(plan["fetch_urls"]).map(&:to_s).map(&:strip).reject(&:blank?)
        from_search = search_results.flat_map do |payload|
          Array(payload["results"]).filter_map { |r| r.is_a?(Hash) ? r["url"].to_s.presence : nil }
        end
        (existing + from_search).uniq.first(MAX_URLS_TO_QUEUE)
      end
    end
  end
end
