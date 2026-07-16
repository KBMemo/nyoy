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
      new(agent_run.chat).resume(agent_run, decision: decision)
    end

    def self.call_for_mcp(instruction:, memo_ref:, chat_id: nil, auto_approve: true, body: nil, title: nil, mode: nil)
      instruction = instruction.to_s.strip
      raise ArgumentError, "instruction required" if instruction.blank?
      raise ArgumentError, "memo_ref required" if memo_ref.to_s.strip.blank?

      chat = McpChatResolver.resolve(chat_id: chat_id, user_content: instruction)
      call(
        chat,
        instruction: instruction,
        auto_approve: auto_approve,
        memo_ref: memo_ref.to_s.strip,
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
      supersede_pending_approvals!

      run = AgentRun.create!(
        chat: @chat,
        graph_name: MemoUpdateGraph::NAME,
        status: "pending",
        current_node: MemoUpdateGraph::START,
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

      Runner.new(run, graph: MemoUpdateGraph.new).call
      run.reload
    end

    def resume(agent_run, decision:)
      raise ArgumentError, "agent run must await approval" unless agent_run.awaiting_approval?
      raise ArgumentError, "decision required" unless %w[approved rejected].include?(decision.to_s)

      agent_run.merge_state!("approval" => decision.to_s)
      Runner.new(agent_run, graph: MemoUpdateGraph.new).call
      agent_run.reload
    end

    private

    def supersede_pending_approvals!
      PendingRunSuperseder.call(
        chat: @chat,
        graph_name: MemoUpdateGraph::NAME,
        reason: "superseded by a newer memo update run"
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
