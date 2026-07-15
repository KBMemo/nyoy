# frozen_string_literal: true

module AgentGraph
  module Nodes
    class PlanResearch
      URL_PATTERN = %r{https?://[^\s<>\]]+}i

      # HITL when the turn implies write/publish/confirm-before-answer.
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
        urls = extract_urls(question)
        replan = state["replan_count"].to_i.positive?
        queries = AgentGraph::SearchQueryNormalizer.queries_for(
          question,
          replan: replan
        )
        hints = revision_hints(state)

        plan = {
          "need_memo" => true,
          "need_web" => web_likely?(question) || replan,
          "queries" => queries,
          "fetch_urls" => urls.first(3),
          "sensitive" => sensitive?(question),
          "revision_hints" => hints,
          "replan" => replan
        }

        AgentGraph::NodeResult.next(
          AgentGraph::ResearchRouting.after_plan(plan),
          updates: {
            "intent" => "research",
            "plan" => plan,
            "budget" => default_budget(state)
          }
        )
      end

      private

      def extract_urls(question)
        question.scan(URL_PATTERN).map { |url| url.sub(/[),.]+$/, "") }.uniq
      end

      def web_likely?(question)
        question.match?(/最新|ニュース|Web|ウェブ|ネット|公式|規格|リリース|調べ|調査|出典|根拠|検索/)
      end

      def sensitive?(question)
        question.match?(SENSITIVE_PATTERN)
      end

      def revision_hints(state)
        return [] if state["replan_count"].to_i <= 0

        hints = [
          "前回ドラフトは却下済み。同じ構成・同じ根拠提示の繰り返しを避ける。",
          "出典・根拠の示し方を変え、不足している視点を補う。"
        ]
        if Array(state["search_results"]).blank?
          hints << "Web 根拠が薄い場合は検索を優先する。"
        end
        hints
      end

      def default_budget(state)
        settings = SearxngSettings.load
        {
          "searches_used" => state.dig("budget", "searches_used").to_i,
          "fetches_used" => state.dig("budget", "fetches_used").to_i,
          "max_searches" => settings.max_searches_per_turn,
          "max_fetches" => settings.max_fetches_per_turn,
          "fetched_urls" => Array(state.dig("budget", "fetched_urls"))
        }
      end
    end
  end
end
