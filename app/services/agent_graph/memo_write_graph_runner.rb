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

      chat = resolve_mcp_chat(chat_id, instruction)
      call(
        chat,
        instruction: instruction,
        auto_approve: auto_approve,
        mcp_body: body.to_s.presence,
        mcp_title: title.to_s.presence
      )
    end

    def self.summary_for(run)
      state = run.state || {}
      draft = state["memo_draft"].is_a?(Hash) ? state["memo_draft"] : {}
      {
        agent_run_id: run.id,
        chat_id: run.chat_id,
        graph_name: run.graph_name,
        status: run.status,
        current_node: run.current_node,
        instruction: state["instruction"],
        draft: state["draft"],
        memo_draft: draft,
        memo_uid: state["memo_uid"],
        final_answer: state["final_answer"],
        approval: state["approval"],
        assistant_message_id: state["assistant_message_id"],
        errors: state["errors"],
        error_message: run.error_message,
        auto_approve: state["auto_approve"] == true,
        nodes: run.agent_node_runs.order(:id).pluck(:node_name),
        chat_path: Rails.application.routes.url_helpers.chat_path(run.chat),
        awaiting_approval: run.awaiting_approval?,
        completed: run.completed?,
        failed: run.failed?
      }
    end

    def self.resolve_mcp_chat(chat_id, instruction)
      if chat_id.present?
        chat = Chat.find_by(id: chat_id)
        raise ArgumentError, "chat not found: #{chat_id}" unless chat

        return chat
      end

      model = ChatModelCatalog.default_model || Model.order(:id).first
      raise ArgumentError, "no chat model available" unless model

      chat = Chat.create!(model: model)
      Message.suppressing_turbo_broadcasts do
        chat.messages.create!(role: :user, content: instruction)
      end
      chat
    end
    private_class_method :resolve_mcp_chat

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
      pending = @chat.agent_runs.pending_decision.where(graph_name: MemoWriteGraph::NAME)
      return if pending.none?

      pending.find_each do |run|
        run.update!(
          status: "cancelled",
          finished_at: Time.current,
          error_message: "superseded by a newer memo write run"
        )
      end
      ApprovalBroadcaster.clear!(@chat)
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
