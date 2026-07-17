# frozen_string_literal: true

module AgentGraph
  class DiagnosticGraph < GraphDefinition
    NAME = "diagnostic"
    START = "record_diagnostic"

    def initialize
      super(
        name: NAME,
        start_node: START,
        nodes: {
          "record_diagnostic" => Nodes::RecordDiagnostic.new
        },
        edges: {
          "record_diagnostic" => Edge.end
        },
        state_schema: DiagnosticStateSchema
      )
    end
  end
end
