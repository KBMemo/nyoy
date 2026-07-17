# frozen_string_literal: true

module AgentGraph
  module Nodes
    class EvaluateEvidence
      def call(state:, run:, chat:)
        review = AgentGraph::RoleServices.fetch(:evidence_evaluator).call(
          state: state,
          run: run,
          chat: chat
        )
        AgentGraph::NodeResult.next(updates: {
          "plan" => review.fetch(:plan).to_h,
          "evidence_review" => {
            "status" => review.fetch(:status).to_s,
            "reason" => review.fetch(:reason).to_s,
            "attempts" => next_attempt(state),
            "next_node" => next_node_for(review.fetch(:status)),
            "target_urls" => review.fetch(:target_urls)
          }.compact
        })
      end

      private

      def next_node_for(status)
        case status
        when "needs_web"
          "search_web"
        when "needs_fetch"
          "fetch_urls"
        else
          "synthesize_draft"
        end
      end

      def next_attempt(state)
        state.dig("evidence_review", "attempts").to_i + 1
      end
    end
  end
end
