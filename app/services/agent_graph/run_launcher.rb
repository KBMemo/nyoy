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

    def self.for_graph(chat:, graph_name:, state:)
      call(
        chat: chat,
        graph: Registry.graph_for(graph_name),
        state: state,
        supersede_reason: Registry.supersede_reason_for(graph_name)
      )
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

      Runner.new(graph: @graph, context: runtime_context(run)).call
      run.reload
    end

    private

    def runtime_context(run)
      ActiveRecordRuntimeContext.build(run: run, graph: @graph)
    end

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
