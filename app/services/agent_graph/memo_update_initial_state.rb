# frozen_string_literal: true

module AgentGraph
  module MemoUpdateInitialState
    module_function

    def build(chat:, instruction:, auto_approve: false, memo_ref: nil, body: nil, title: nil, mode: nil)
      MemoUpdateStateSchema.validate!({
        "instruction" => instruction.to_s,
        "chat_id" => chat.id,
        "intent" => "memo_update",
        "plan" => {},
        "memo_ref" => nil,
        "source_body" => nil,
        "source_title" => nil,
        "original_memo" => nil,
        "memo_draft" => nil,
        "draft" => nil,
        "memo_uid" => nil,
        "memo_result" => nil,
        "final_answer" => nil,
        "approval" => nil,
        "auto_approve" => auto_approve == true,
        "mcp_memo_ref" => memo_ref,
        "mcp_body" => body,
        "mcp_title" => title,
        "mcp_mode" => mode,
        "errors" => [],
        "next_node" => MemoUpdateGraph::START
      })
    end
  end
end
