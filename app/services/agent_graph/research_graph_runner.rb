# frozen_string_literal: true

module AgentGraph
  class ResearchGraphRunner
    def self.call(chat, question: nil, auto_approve: false)
      new(chat, question: question, auto_approve: auto_approve).call
    end

    def self.resume(agent_run, decision:)
      raise ArgumentError, "Research Graph approval resume is no longer supported"
    end

    # MCP entry: create or reuse a chat, then run the Research Graph.
    def self.call_for_mcp(question:, chat_id: nil, auto_approve: true)
      question = question.to_s.strip
      raise ArgumentError, "question required" if question.blank?

      chat = resolve_mcp_chat(chat_id, question)
      call(chat, question: question, auto_approve: auto_approve)
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
        state: ResearchInitialState.build(
          chat: @chat,
          question: question,
          auto_approve: @auto_approve
        )
      )

      Runner.new(run, graph: ResearchGraph.new).call
      run.reload
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
