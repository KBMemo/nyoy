# frozen_string_literal: true

module AgentGraph
  class ResearchGraphRunner
    def self.call(chat, question: nil, auto_approve: false, routing: nil)
      new(chat, question: question, auto_approve: auto_approve, routing: routing).call
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

    def initialize(chat, question: nil, auto_approve: false, routing: nil)
      @chat = chat
      @question = question.to_s.strip.presence
      @auto_approve = auto_approve
      @routing = routing
    end

    def call
      question = ensure_question!

      RunLauncher.for_graph(
        chat: @chat,
        graph_name: ResearchGraph::NAME,
        state: ResearchInitialState.build(
          chat: @chat,
          question: question,
          auto_approve: @auto_approve,
          routing: @routing
        )
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
