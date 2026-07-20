# frozen_string_literal: true

module AgentGraph
  # Selects the graph for a chat turn. Keep this deterministic and conservative:
  # false negatives fall back to the normal chat/tool loop.
  module Router
    Decision = Data.define(:graph_name, :runner, :args, :intent_decision) do
      def memo_write?
        graph_name == MemoWriteGraph::NAME
      end

      def memo_update?
        graph_name == MemoUpdateGraph::NAME
      end

      def research?
        graph_name == ResearchGraph::NAME
      end

      def image_understanding?
        graph_name == ImageUnderstandingGraph::NAME
      end
    end

    module_function

    def route(chat)
      message = latest_user_message(chat)
      text = message&.content.to_s.strip
      routed = RoleServices.fetch(:intent).call(chat: chat, message: message, text: text)
      return nil unless routed

      decision(routed.fetch(:graph_name), routed.fetch(:intent_decision))
    end

    def latest_user_text(chat)
      latest_user_message(chat)&.content.to_s.strip
    end

    def latest_user_message(chat)
      chat.messages.where(role: :user).order(:id).last
    end

    def decision(graph_name, intent_decision)
      Decision.new(
        graph_name: graph_name,
        runner: Registry.runner_for(graph_name),
        args: runner_args(graph_name, intent_decision),
        intent_decision: intent_decision
      )
    end

    def runner_args(graph_name, intent_decision)
      return {} unless graph_name == ResearchGraph::NAME

      { routing: intent_decision }
    end
    private_class_method :runner_args
    private_class_method :decision
  end
end
