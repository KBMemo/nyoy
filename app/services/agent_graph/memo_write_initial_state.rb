# frozen_string_literal: true

module AgentGraph
  module MemoWriteInitialState
    module_function

    def build(chat:, instruction:, auto_approve: false, mcp_body: nil, mcp_title: nil)
      MemoWriteStateSchema.validate!({
        "instruction" => instruction.to_s,
        "chat_id" => chat.id,
        "intent" => "memo_write",
        "plan" => {},
        "memo_draft" => nil,
        "draft" => nil,
        "memo_uid" => nil,
        "memo_result" => nil,
        "final_answer" => nil,
        "approval" => nil,
        "auto_approve" => auto_approve == true,
        "mcp_body" => mcp_body,
        "mcp_title" => mcp_title,
        "errors" => [],
        "next_node" => MemoWriteGraph::START
      })
    end
  end
end
