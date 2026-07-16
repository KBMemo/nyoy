# frozen_string_literal: true

module AgentGraph
  class MemoUpdateGraphRunner
    def self.call(chat, instruction: nil, auto_approve: false, memo_ref: nil, body: nil, title: nil, mode: nil)
      new(
        chat,
        instruction: instruction,
        auto_approve: auto_approve,
        memo_ref: memo_ref,
        body: body,
        title: title,
        mode: mode
      ).call
    end

    def self.resume(agent_run, decision:)
      RunResumer.for_graph(agent_run, graph_name: MemoUpdateGraph::NAME, decision: decision)
    end

    def self.call_for_mcp(instruction:, memo_ref:, chat_id: nil, auto_approve: true, body: nil, title: nil, mode: nil)
      chat, instruction = McpRunRequest.resolve(
        chat_id: chat_id,
        user_content: instruction,
        required_name: "instruction"
      )
      memo_ref = McpRunRequest.required_string(memo_ref, name: "memo_ref")
      call(
        chat,
        instruction: instruction,
        auto_approve: auto_approve,
        memo_ref: memo_ref,
        body: body.to_s.presence,
        title: title.to_s.presence,
        mode: mode.to_s.presence
      )
    end

    def initialize(chat, instruction: nil, auto_approve: false, memo_ref: nil, body: nil, title: nil, mode: nil)
      @chat = chat
      @instruction = instruction.to_s.strip.presence
      @auto_approve = auto_approve
      @memo_ref = memo_ref
      @body = body
      @title = title
      @mode = mode
    end

    def call
      instruction = ensure_instruction!

      RunLauncher.for_graph(
        chat: @chat,
        graph_name: MemoUpdateGraph::NAME,
        state: MemoUpdateInitialState.build(
          chat: @chat,
          instruction: instruction,
          auto_approve: @auto_approve,
          memo_ref: @memo_ref,
          body: @body,
          title: @title,
          mode: @mode
        )
      )
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
