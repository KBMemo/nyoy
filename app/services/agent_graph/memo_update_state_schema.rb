# frozen_string_literal: true

module AgentGraph
  module MemoUpdateStateSchema
    REQUIRED_KEYS = %w[
      instruction
      chat_id
      intent
      plan
      memo_ref
      source_body
      source_title
      original_memo
      memo_draft
      draft
      memo_uid
      memo_result
      final_answer
      approval
      auto_approve
      mcp_memo_ref
      mcp_body
      mcp_title
      mcp_mode
      errors
      next_node
    ].freeze

    SCHEMA = StateSchema.new(
      name: MemoUpdateGraph::NAME,
      required_keys: REQUIRED_KEYS
    )

    module_function

    def validate!(state)
      SCHEMA.validate!(state)
    end
  end
end
