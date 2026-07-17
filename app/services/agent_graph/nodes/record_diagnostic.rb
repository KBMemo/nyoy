# frozen_string_literal: true

module AgentGraph
  module Nodes
    class RecordDiagnostic
      def call(state:, run:, chat:)
        note = state["note"].to_s.strip
        AgentGraph::NodeResult.end(
          updates: {
            "final_answer" => note.present? ? "Diagnostic Graph completed: #{note}" : "Diagnostic Graph completed"
          }
        )
      end
    end
  end
end
