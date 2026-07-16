# frozen_string_literal: true

module AgentGraph
  # Launches a duplicate run from a retry dry-run plan. This intentionally keeps
  # the original failed run immutable so its node/checkpoint audit log remains a
  # faithful record of the failure.
  class RunRetryLauncher
    def self.call(agent_run)
      new(agent_run).call
    end

    def initialize(agent_run)
      @agent_run = agent_run
    end

    def call
      plan = RunRetryPlanner.call(@agent_run)
      raise ArgumentError, plan.reason unless plan.retryable

      graph = Registry.graph_for(@agent_run.graph_name)
      retry_run = AgentRun.create!(
        chat: @agent_run.chat,
        graph_name: graph.name,
        status: "pending",
        current_node: plan.next_node,
        state: retry_state(plan)
      )

      Runner.new(retry_run, graph: graph).call
      retry_run.reload
    end

    private

    def retry_state(plan)
      (plan.checkpoint.state || {}).deep_dup.merge(
        "retry_of_agent_run_id" => @agent_run.id,
        "retry_from_checkpoint_id" => plan.checkpoint.id,
        "retry_from_node" => plan.checkpoint.node_name
      )
    end
  end
end
