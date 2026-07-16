# frozen_string_literal: true

module AgentGraph
  class MemoUpdateRunSummary
    def self.build(run)
      new(run).build
    end

    def initialize(run)
      @run = run
      @state = run.state || {}
    end

    def build
      {
        agent_run_id: @run.id,
        chat_id: @run.chat_id,
        graph_name: @run.graph_name,
        status: @run.status,
        current_node: @run.current_node,
        instruction: @state["instruction"],
        memo_ref: @state["memo_ref"],
        draft: @state["draft"],
        memo_draft: memo_draft,
        memo_uid: @state["memo_uid"],
        final_answer: @state["final_answer"],
        approval: @state["approval"],
        assistant_message_id: @state["assistant_message_id"],
        errors: @state["errors"],
        error_message: @run.error_message,
        auto_approve: @state["auto_approve"] == true,
        nodes: @run.agent_node_runs.order(:id).pluck(:node_name),
        chat_path: Rails.application.routes.url_helpers.chat_path(@run.chat),
        awaiting_approval: @run.awaiting_approval?,
        completed: @run.completed?,
        failed: @run.failed?
      }
    end

    private

    def memo_draft
      @state["memo_draft"].is_a?(Hash) ? @state["memo_draft"] : {}
    end
  end
end
