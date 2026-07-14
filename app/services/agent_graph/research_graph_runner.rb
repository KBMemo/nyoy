# frozen_string_literal: true

module AgentGraph
  class ResearchGraphRunner
    def self.call(chat, question: nil, auto_approve: false)
      new(chat, question: question, auto_approve: auto_approve).call
    end

    def self.resume(agent_run, decision:)
      new(agent_run.chat).resume(agent_run, decision: decision)
    end

    # MCP entry: create or reuse a chat, then run the Research Graph.
    def self.call_for_mcp(question:, chat_id: nil, auto_approve: true)
      question = question.to_s.strip
      raise ArgumentError, "question required" if question.blank?

      chat = resolve_mcp_chat(chat_id, question)
      call(chat, question: question, auto_approve: auto_approve)
    end

    def self.summary_for(run)
      state = run.state || {}
      {
        agent_run_id: run.id,
        chat_id: run.chat_id,
        graph_name: run.graph_name,
        status: run.status,
        current_node: run.current_node,
        question: state["question"],
        draft: state["draft"],
        final_answer: state["final_answer"],
        approval: state["approval"],
        assistant_message_id: state["assistant_message_id"],
        plan: state["plan"],
        errors: state["errors"],
        error_message: run.error_message,
        auto_approve: state["auto_approve"] == true,
        replan_count: state["replan_count"].to_i,
        rejection_notes: state["rejection_notes"],
        nodes: run.agent_node_runs.order(:id).pluck(:node_name),
        chat_path: Rails.application.routes.url_helpers.chat_path(run.chat),
        awaiting_approval: run.awaiting_approval?,
        completed: run.completed?,
        failed: run.failed?,
        replans_remaining: [
          AgentGraph::Nodes::AwaitApproval::MAX_REPLANS - state["replan_count"].to_i,
          0
        ].max
      }
    end

    def self.resolve_mcp_chat(chat_id, question)
      if chat_id.present?
        chat = Chat.find_by(id: chat_id)
        raise ArgumentError, "chat not found: #{chat_id}" unless chat

        return chat
      end

      model = ChatModelCatalog.default_model || Model.order(:id).first
      raise ArgumentError, "no chat model available" unless model

      chat = Chat.create!(model: model)
      Message.suppressing_turbo_broadcasts do
        chat.messages.create!(role: :user, content: question)
      end
      chat
    end
    private_class_method :resolve_mcp_chat

    def initialize(chat, question: nil, auto_approve: false)
      @chat = chat
      @question = question.to_s.strip.presence
      @auto_approve = auto_approve
    end

    def call
      question = ensure_question!
      supersede_pending_approvals!

      run = AgentRun.create!(
        chat: @chat,
        graph_name: ResearchGraph::NAME,
        status: "pending",
        current_node: ResearchGraph::START,
        state: {
          "question" => question,
          "chat_id" => @chat.id,
          "intent" => "research",
          "plan" => {},
          "memo_context" => nil,
          "search_results" => [],
          "fetched_pages" => [],
          "draft" => nil,
          "final_answer" => nil,
          "approval" => nil,
          "auto_approve" => @auto_approve == true,
          "budget" => {},
          "errors" => [],
          "replan_count" => 0,
          "rejection_notes" => [],
          "next_node" => ResearchGraph::START
        }
      )

      Runner.new(run, graph: ResearchGraph.new).call
      run.reload
    end

    def resume(agent_run, decision:)
      raise ArgumentError, "agent run must await approval" unless agent_run.awaiting_approval?
      raise ArgumentError, "decision required" unless %w[approved rejected].include?(decision.to_s)

      agent_run.merge_state!("approval" => decision.to_s)
      Runner.new(agent_run, graph: ResearchGraph.new).call
      agent_run.reload
    end

    private

    def supersede_pending_approvals!
      pending = @chat.agent_runs.pending_decision.where(graph_name: ResearchGraph::NAME)
      return if pending.none?

      pending.find_each do |run|
        run.update!(
          status: "cancelled",
          finished_at: Time.current,
          error_message: "superseded by a newer research run"
        )
      end
      ApprovalBroadcaster.clear!(@chat)
    end

    def ensure_question!
      question = @question.presence || latest_user_question
      raise ArgumentError, "user question required" if question.blank?

      if @question.present? && latest_user_question != @question
        Message.suppressing_turbo_broadcasts do
          @chat.messages.create!(role: :user, content: @question)
        end
      end

      question
    end

    def latest_user_question
      @chat.messages.where(role: :user).order(:id).last&.content.to_s.strip
    end
  end
end
