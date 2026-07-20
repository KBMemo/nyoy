# frozen_string_literal: true

module AgentGraph
  module Nodes
    class PlanResearch
      def call(state:, run:, chat:)
        plan = AgentGraph::RoleServices.fetch(:planner).call(
          state: state,
          run: run,
          chat: chat
        )
        plan = plan.to_h.stringify_keys

        AgentGraph::NodeResult.next(
          AgentGraph::ResearchRouting.after_plan(plan),
          updates: {
            "intent" => "research",
            "plan" => plan,
            "planning" => {
              "role" => "planner",
              "profile" => AgentGraph::RoleServices.active_profile_for(:planner).to_s
            },
            "budget" => default_budget(state)
          }
        )
      end

      private

      def default_budget(state)
        settings = SearfrontSettings.load
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
