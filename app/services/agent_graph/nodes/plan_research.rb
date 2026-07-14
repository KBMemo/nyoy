# frozen_string_literal: true

module AgentGraph
  module Nodes
    class PlanResearch
      def call(state:, run:, chat:)
        question = state.fetch("question").to_s
        need_memo = memo_likely?(question)
        need_web = web_likely?(question)

        plan = {
          "need_memo" => need_memo,
          "need_web" => need_web,
          "queries" => [ question.truncate(120) ],
          "fetch_urls" => [],
          "sensitive" => false
        }

        AgentGraph::NodeResult.next(
          need_memo ? "recall_memos" : "finalize_answer",
          updates: {
            "intent" => "research",
            "plan" => plan,
            "budget" => default_budget(state)
          }
        )
      end

      private

      def memo_likely?(_question)
        # R0 always consults memos for research turns; web/fetch come in R1.
        true
      end

      def web_likely?(question)
        question.match?(/最新|ニュース|Web|ウェブ|ネット|公式|規格|リリース/)
      end

      def default_budget(state)
        settings = SearxngSettings.load
        {
          "searches_used" => state.dig("budget", "searches_used").to_i,
          "fetches_used" => state.dig("budget", "fetches_used").to_i,
          "max_searches" => settings.max_searches_per_turn,
          "max_fetches" => settings.max_fetches_per_turn
        }
      end
    end
  end
end
