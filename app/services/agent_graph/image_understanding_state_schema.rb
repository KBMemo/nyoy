# frozen_string_literal: true

module AgentGraph
  module ImageUnderstandingStateSchema
    REQUIRED_KEYS = %w[
      question
      chat_id
      intent
      plan
      image_source
      analysis
      final_answer
      approval
      auto_approve
      errors
      next_node
    ].freeze

    SCHEMA = StateSchema.new(
      name: ImageUnderstandingGraph::NAME,
      required_keys: REQUIRED_KEYS
    )

    module_function

    def validate!(state)
      SCHEMA.validate!(state)
    end
  end
end
