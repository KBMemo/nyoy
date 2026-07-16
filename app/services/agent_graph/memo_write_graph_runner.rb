# frozen_string_literal: true

module AgentGraph
  class MemoWriteGraphRunner
    def self.call(chat, instruction: nil, auto_approve: false, mcp_body: nil, mcp_title: nil)
      new(
        chat,
        instruction: instruction,
        auto_approve: auto_approve,
        mcp_body: mcp_body,
        mcp_title: mcp_title
      ).call
    end

    def self.resume(agent_run, decision:)
      new(agent_run.chat).resume(agent_run, decision: decision)
    end

    def self.call_for_mcp(instruction:, chat_id: nil, auto_approve: true, body: nil, title: nil)
      chat, instruction = McpRunRequest.resolve(
        chat_id: chat_id,
        user_content: instruction,
        required_name: "instruction"
      )
      call(
        chat,
        instruction: instruction,
        auto_approve: auto_approve,
        mcp_body: body.to_s.presence,
        mcp_title: title.to_s.presence
      )
    end

    def initialize(chat, instruction: nil, auto_approve: false, mcp_body: nil, mcp_title: nil)
      @chat = chat
      @instruction = instruction.to_s.strip.presence
      @auto_approve = auto_approve
      @mcp_body = mcp_body
      @mcp_title = mcp_title
    end

    def call
      instruction = ensure_instruction!

      RunLauncher.for_graph(
        chat: @chat,
        graph_name: MemoWriteGraph::NAME,
        state: MemoWriteInitialState.build(
          chat: @chat,
          instruction: instruction,
          auto_approve: @auto_approve,
          mcp_body: @mcp_body,
          mcp_title: @mcp_title
        )
      )
    end

    def resume(agent_run, decision:)
      RunResumer.for_graph(agent_run, graph_name: MemoWriteGraph::NAME, decision: decision)
    end

    private

    def ensure_instruction!
      UserTurnResolver.call(
        chat: @chat,
        explicit_content: @instruction,
        required_label: "user instruction"
      )
    end
  end
end
