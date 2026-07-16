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
      supersede_pending_approvals!

      run = AgentRun.create!(
        chat: @chat,
        graph_name: MemoWriteGraph::NAME,
        status: "pending",
        current_node: MemoWriteGraph::START,
        state: MemoWriteInitialState.build(
          chat: @chat,
          instruction: instruction,
          auto_approve: @auto_approve,
          mcp_body: @mcp_body,
          mcp_title: @mcp_title
        )
      )

      Runner.new(run, graph: MemoWriteGraph.new).call
      run.reload
    end

    def resume(agent_run, decision:)
      raise ArgumentError, "agent run must await approval" unless agent_run.awaiting_approval?
      raise ArgumentError, "decision required" unless %w[approved rejected].include?(decision.to_s)

      agent_run.merge_state!("approval" => decision.to_s)
      Runner.new(agent_run, graph: MemoWriteGraph.new).call
      agent_run.reload
    end

    private

    def supersede_pending_approvals!
      PendingRunSuperseder.call(
        chat: @chat,
        graph_name: MemoWriteGraph::NAME,
        reason: "superseded by a newer memo write run"
      )
    end

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
