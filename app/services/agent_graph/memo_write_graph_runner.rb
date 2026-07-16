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
      instruction = instruction.to_s.strip
      raise ArgumentError, "instruction required" if instruction.blank?

      chat = McpChatResolver.resolve(chat_id: chat_id, user_content: instruction)
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
      graph = MemoWriteGraph.new

      RunLauncher.call(
        chat: @chat,
        graph: graph,
        state: MemoWriteInitialState.build(
          chat: @chat,
          instruction: instruction,
          auto_approve: @auto_approve,
          mcp_body: @mcp_body,
          mcp_title: @mcp_title
        ),
        supersede_reason: "superseded by a newer memo write run"
      )
    end

    def resume(agent_run, decision:)
      RunResumer.call(agent_run, graph: MemoWriteGraph.new, decision: decision)
    end

    private

    def ensure_instruction!
      instruction = @instruction.presence || latest_user_instruction
      raise ArgumentError, "user instruction required" if instruction.blank?

      if @instruction.present? && latest_user_instruction != @instruction
        Message.suppressing_turbo_broadcasts do
          @chat.messages.create!(role: :user, content: @instruction)
        end
      end

      instruction
    end

    def latest_user_instruction
      @chat.messages.where(role: :user).order(:id).last&.content.to_s.strip
    end
  end
end
