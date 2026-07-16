# frozen_string_literal: true

module AgentGraph
  module PendingRunSuperseder
    module_function

    def call(chat:, graph_name:, reason:)
      pending = chat.agent_runs.pending_decision.where(graph_name: graph_name)
      return if pending.none?

      pending.find_each do |run|
        run.update!(
          status: "cancelled",
          finished_at: Time.current,
          error_message: reason
        )
      end
      ApprovalBroadcaster.clear!(chat)
    end
  end
end
