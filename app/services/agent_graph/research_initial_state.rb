# frozen_string_literal: true

module AgentGraph
  module ResearchInitialState
    module_function

    def build(chat:, question:, auto_approve: false, routing: nil)
      ResearchStateSchema.validate!({
        "question" => question.to_s,
        "chat_id" => chat.id,
        "intent" => "research",
        "routing" => routing.to_h.deep_stringify_keys,
        "plan" => {},
        "planning" => {},
        "memo_context" => nil,
        "search_results" => [],
        "fetched_pages" => [],
        "evidence_review" => {},
        "draft" => nil,
        "final_answer" => nil,
        "approval" => nil,
        "auto_approve" => auto_approve == true,
        "budget" => {},
        "errors" => [],
        "next_node" => ResearchGraph::START
      })
    end
  end
end
