# frozen_string_literal: true

module AgentGraph
  module Nodes
    class RecallMemos
      def call(state:, run:, chat:)
        plan = state.fetch("plan", {})
        unless plan["need_memo"]
          return AgentGraph::NodeResult.next(AgentGraph::ResearchRouting.after_recall(state))
        end

        query = Array(plan["queries"]).first.presence || state.fetch("question")
        result = ChatTools::RecallMemos.new(chat: chat).execute(query: query)
        AgentGraph::ToolTraceRecorder.record!(
          chat,
          name: "recall_memos",
          arguments: { "query" => query },
          result: result
        )

        if result.is_a?(Hash) && result[:error]
          return AgentGraph::NodeResult.next(
            AgentGraph::ResearchRouting.after_recall(state),
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
          AgentGraph::ResearchRouting.after_recall(state),
          updates: {
            "memo_context" => result.is_a?(Hash) ? result[:context] : nil
          }
        )
      end
    end
  end
end
