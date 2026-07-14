# frozen_string_literal: true

module AgentGraph
  class ResearchGraphRunner
    def self.call(chat)
      new(chat).call
    end

    def initialize(chat)
      @chat = chat
    end

    def call
      question = latest_user_question
      raise ArgumentError, "user question required" if question.blank?

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
          "budget" => {},
          "errors" => [],
          "next_node" => ResearchGraph::START
        }
      )

      Runner.new(run, graph: ResearchGraph.new).call
      run.reload
    end

    private

    def latest_user_question
      @chat.messages.where(role: :user).order(:id).last&.content.to_s.strip
    end
  end
end
