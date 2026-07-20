# frozen_string_literal: true

module AgentGraph
  module Nodes
    class EvaluateEvidence
      def call(state:, run:, chat:)
        result = AgentGraph::RoleServices.fetch(:evidence_evaluator).call(
          state: state,
          run: run,
          chat: chat
        )
        review, metadata = result.is_a?(Array) ? result : [ result, {} ]
        metadata = metadata.to_h.stringify_keys

        AgentGraph::NodeResult.next(updates: {
          "plan" => review.fetch(:plan).to_h,
          "evidence_review" => metadata.merge({
            "status" => review.fetch(:status).to_s,
            "reason" => review.fetch(:reason).to_s,
            "attempts" => next_attempt(state),
            "next_node" => next_node_for(review.fetch(:status)),
            "target_urls" => review.fetch(:target_urls),
            "role" => "evidence_evaluator",
            "profile" => AgentGraph::RoleServices.active_profile_for(:evidence_evaluator).to_s
          }.compact)
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
