# frozen_string_literal: true

module AgentGraph
  class ActiveRecordRuntimeContext
    def self.build(run:, graph:)
      RuntimeContext.new(
        run: run,
        graph: graph,
        store: ActiveRecordRunStore.new(run: run, graph: graph),
        signals: RailsRuntimeSignals.new
      )
    end
  end
end
