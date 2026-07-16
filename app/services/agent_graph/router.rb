# frozen_string_literal: true

module AgentGraph
  # Selects the graph for a chat turn. Keep this deterministic and conservative:
  # false negatives fall back to the normal chat/tool loop.
  module Router
    Decision = Data.define(:graph_name, :runner, :args, :intent_decision) do
      def memo_write?
        graph_name == MemoWriteGraph::NAME
      end

      def research?
        graph_name == ResearchGraph::NAME
      end
    end

    module_function

    def route(chat)
      text = latest_user_text(chat)
      return nil if text.blank?

      memo_update = MemoUpdateIntent.decision(text)
      return decision(MemoUpdateGraph::NAME, memo_update) if memo_update[:match]

      memo_write = MemoWriteIntent.decision(text)
      return decision(MemoWriteGraph::NAME, memo_write) if memo_write[:match]

      research = ResearchIntent.decision(text)
      return decision(ResearchGraph::NAME, research) if research[:match]

      nil
    end

    def latest_user_text(chat)
      chat.messages.where(role: :user).order(:id).last&.content.to_s.strip
    end

    def decision(graph_name, intent_decision)
      Decision.new(
        graph_name: graph_name,
        runner: Registry.runner_for(graph_name),
        args: {},
        intent_decision: intent_decision
      )
    end
    private_class_method :decision
  end
end
