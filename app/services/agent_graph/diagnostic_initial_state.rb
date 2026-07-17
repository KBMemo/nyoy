# frozen_string_literal: true

module AgentGraph
  module DiagnosticInitialState
    module_function

    def build(chat:, note: nil)
      DiagnosticStateSchema.validate!({
        "chat_id" => chat.id,
        "intent" => "diagnostic",
        "note" => note.to_s,
        "final_answer" => nil,
        "approval" => "not_required",
        "auto_approve" => true,
        "errors" => [],
        "next_node" => DiagnosticGraph::START
      })
    end
  end
end
