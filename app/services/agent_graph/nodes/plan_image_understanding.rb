# frozen_string_literal: true

module AgentGraph
  module Nodes
    class PlanImageUnderstanding
      def call(state:, run:, chat:)
        plan = (state["plan"] || {}).merge(
          "question" => state.fetch("question").to_s,
          "needs_vision" => true
        )

        AgentGraph::NodeResult.next(
          updates: {
            "intent" => "image_understanding",
            "plan" => plan,
            "approval" => "not_required"
          }
        )
      end
    end
  end
end
