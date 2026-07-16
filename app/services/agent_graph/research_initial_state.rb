# frozen_string_literal: true

module AgentGraph
  module ResearchInitialState
    module_function

    def build(chat:, question:, auto_approve: false)
      ResearchStateSchema.validate!({
        "question" => question.to_s,
        "chat_id" => chat.id,
        "intent" => "research",
        "plan" => {},
        "memo_context" => nil,
        "search_results" => [],
        "fetched_pages" => [],
        "draft" => nil,
        "final_answer" => nil,
        "approval" => nil,
        "auto_approve" => auto_approve == true,
        "budget" => {},
        "errors" => [],
        "replan_count" => 0,
        "rejection_notes" => [],
        "next_node" => ResearchGraph::START
      })
    end
  end
end
