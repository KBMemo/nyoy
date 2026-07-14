# frozen_string_literal: true

module AgentGraph
  module Nodes
    class RecallMemos
      def call(state:, run:, chat:)
        plan = state.fetch("plan", {})
        unless plan["need_memo"]
          return AgentGraph::NodeResult.next("finalize_answer")
        end

        query = Array(plan["queries"]).first.presence || state.fetch("question")
        result = ChatTools::RecallMemos.new(chat: chat).execute(query: query)

        if result.is_a?(Hash) && result[:error]
          return AgentGraph::NodeResult.next(
            "finalize_answer",
            updates: {
              "memo_context" => nil,
              "errors" => Array(state["errors"]) + [ {
                "node" => "recall_memos",
                "code" => "RECALL_FAILED",
                "message" => result[:error].to_s
              } ]
            }
          )
        end

        AgentGraph::NodeResult.next(
          "finalize_answer",
          updates: {
            "memo_context" => result.is_a?(Hash) ? result[:context] : nil
          }
        )
      end
    end
  end
end
