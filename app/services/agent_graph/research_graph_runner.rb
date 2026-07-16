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
      chat, question = McpRunRequest.resolve(
        chat_id: chat_id,
        user_content: question,
        required_name: "question"
      )
      call(chat, question: question, auto_approve: auto_approve)
    end

    def initialize(chat, question: nil, auto_approve: false)
      @chat = chat
      @question = question.to_s.strip.presence
      @auto_approve = auto_approve
    end

    def call
      question = ensure_question!
      graph = ResearchGraph.new

      RunLauncher.call(
        chat: @chat,
        graph: graph,
        state: ResearchInitialState.build(
          chat: @chat,
          question: question,
          auto_approve: @auto_approve
        ),
        supersede_reason: "superseded by a newer research run"
      )
    end

    private

    def ensure_question!
      UserTurnResolver.call(
        chat: @chat,
        explicit_content: @question,
        required_label: "user question"
      )
    end
  end
end
