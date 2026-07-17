# frozen_string_literal: true

module AgentGraph
  module DiagnosticStateSchema
    module_function

    SCHEMA = StateSchema.new(
      name: "diagnostic",
      required_keys: %w[
        chat_id
        intent
        note
        final_answer
        approval
        auto_approve
        errors
        next_node
      ]
    )

    def validate!(state)
      SCHEMA.validate!(state)
    end
  end
end
