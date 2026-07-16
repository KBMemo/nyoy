# frozen_string_literal: true

module AgentGraph
  class RunLauncher
    def self.call(chat:, graph:, state:, supersede_reason: nil)
      new(
        chat: chat,
        graph: graph,
        state: state,
        supersede_reason: supersede_reason
      ).call
    end

    def initialize(chat:, graph:, state:, supersede_reason: nil)
      @chat = chat
      @graph = graph
      @state = state
      @supersede_reason = supersede_reason
    end

    def call
      supersede_pending_approvals!

      run = AgentRun.create!(
        chat: @chat,
        graph_name: @graph.name,
        status: "pending",
        current_node: @graph.start_node,
        state: @state
      )

      Runner.new(run, graph: @graph).call
      run.reload
    end

    private

    def supersede_pending_approvals!
      return if @supersede_reason.blank?

      PendingRunSuperseder.call(
        chat: @chat,
        graph_name: @graph.name,
        reason: @supersede_reason
      )
    end
  end
end
