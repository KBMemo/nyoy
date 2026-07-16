# frozen_string_literal: true

module AgentGraph
  class RunSummaryBase
    def self.build(run)
      new(run).build
    end

    def initialize(run)
      @run = run
      @state = run.state || {}
    end

    private

    attr_reader :run, :state

    def common_fields
      {
        agent_run_id: run.id,
        chat_id: run.chat_id,
        graph_name: run.graph_name,
        status: run.status,
        current_node: run.current_node
      }
    end

    def status_fields
      {
        error_message: run.error_message,
        auto_approve: state["auto_approve"] == true,
        nodes: run.agent_node_runs.order(:id).pluck(:node_name),
        chat_path: Rails.application.routes.url_helpers.chat_path(run.chat),
        awaiting_approval: run.awaiting_approval?,
        completed: run.completed?,
        failed: run.failed?
      }
    end

    def memo_draft
      state["memo_draft"].is_a?(Hash) ? state["memo_draft"] : {}
    end
  end
end
