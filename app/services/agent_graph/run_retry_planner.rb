# frozen_string_literal: true

module AgentGraph
  # Dry-run planner for failed-run retry. It does not mutate runs; callers use
  # this to show whether a future duplicate-run retry would be safe enough.
  module RunRetryPlanner
    Plan = Data.define(:retryable, :reason, :checkpoint, :next_node, :graph_name)

    module_function

    def call(agent_run)
      return plan(false, "failed run のみ retry 検討対象です", graph_name: agent_run.graph_name) unless agent_run.failed?

      graph = Registry.graph_for(agent_run.graph_name)
      checkpoint = latest_successful_checkpoint(agent_run)
      return plan(false, "成功済み checkpoint がありません", graph_name: graph.name) unless checkpoint

      next_node = graph.next_node_for(checkpoint.node_name, checkpoint.state || {})
      return plan(false, "checkpoint が終端 node のため次 node がありません", checkpoint: checkpoint, graph_name: graph.name) if next_node.blank?

      if Registry.approval_supported?(agent_run.graph_name)
        return plan(
          false,
          "write 系 Graph は外部書き込みの部分成功を確認してから手動 retry してください",
          checkpoint: checkpoint,
          next_node: next_node,
          graph_name: graph.name
        )
      end

      plan(true, "複製 run 候補", checkpoint: checkpoint, next_node: next_node, graph_name: graph.name)
    rescue ArgumentError => e
      plan(false, e.message, graph_name: agent_run.graph_name)
    rescue StandardError => e
      plan(false, "retry plan failed: #{e.message}", graph_name: agent_run.graph_name)
    end

    def latest_successful_checkpoint(agent_run)
      completed_node = agent_run.agent_node_runs.where(status: "completed").order(:id).last
      return unless completed_node

      agent_run.agent_checkpoints
        .where(node_name: completed_node.node_name)
        .where("created_at >= ?", completed_node.finished_at || completed_node.created_at)
        .order(:id)
        .last || agent_run.agent_checkpoints.where(node_name: completed_node.node_name).order(:id).last
    end
    private_class_method :latest_successful_checkpoint

    def plan(retryable, reason, checkpoint: nil, next_node: nil, graph_name: nil)
      Plan.new(
        retryable: retryable,
        reason: reason,
        checkpoint: checkpoint,
        next_node: next_node,
        graph_name: graph_name
      )
    end
    private_class_method :plan
  end
end
