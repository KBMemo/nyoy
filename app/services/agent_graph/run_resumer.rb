# frozen_string_literal: true

module AgentGraph
  class RunResumer
    VALID_DECISIONS = %w[approved rejected].freeze

    def self.call(agent_run, graph:, decision:)
      new(agent_run, graph: graph, decision: decision).call
    end

    def self.for_graph(agent_run, graph_name:, decision:)
      call(
        agent_run,
        graph: Registry.graph_for(graph_name),
        decision: decision
      )
    end

    def initialize(agent_run, graph:, decision:)
      @agent_run = agent_run
      @graph = graph
      @decision = decision.to_s
    end

    def call
      raise ArgumentError, "agent run graph mismatch: #{@agent_run.graph_name} != #{@graph.name}" if @agent_run.graph_name != @graph.name
      raise ArgumentError, "agent run must await approval" unless @agent_run.awaiting_approval?
      raise ArgumentError, "decision required" unless VALID_DECISIONS.include?(@decision)

      @agent_run.merge_state!("approval" => @decision)
      Runner.new(graph: @graph, context: runtime_context).call
      @agent_run.reload
    end

    private

    def runtime_context
      ActiveRecordRuntimeContext.build(run: @agent_run, graph: @graph)
    end
  end
end
