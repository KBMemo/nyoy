# frozen_string_literal: true

module AgentGraph
  module Nodes
    class FinalizeImageAnswer
      def call(state:, run:, chat:)
        analysis = state["analysis"].to_s.strip
        return AgentGraph::NodeResult.fail("missing image analysis for finalize") if analysis.blank?

        message = AgentGraph::AssistantMessagePublisher.call(chat, content: analysis)

        AgentGraph::NodeResult.end(
          updates: {
            "final_answer" => analysis,
            "assistant_message_id" => message.id
          }
        )
      end
    end
  end
end
