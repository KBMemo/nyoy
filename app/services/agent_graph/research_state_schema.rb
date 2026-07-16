# frozen_string_literal: true

module AgentGraph
  module ResearchStateSchema
    REQUIRED_KEYS = %w[
      question
      chat_id
      intent
      plan
      memo_context
      search_results
      fetched_pages
      draft
      final_answer
      approval
      auto_approve
      budget
      errors
      replan_count
      rejection_notes
      next_node
    ].freeze

    SCHEMA = StateSchema.new(
      name: ResearchGraph::NAME,
      required_keys: REQUIRED_KEYS
    )

    module_function

    def validate!(state)
      SCHEMA.validate!(state)
    end
  end
end
