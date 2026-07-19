# frozen_string_literal: true

module AgentGraph
  class RailsRuntimeSignals
    def check_cancelled!(run)
      ChatResponseControl.check!(run.chat_id)
    end

    def node_started!(run, node_name)
      ProgressBroadcaster.started!(run.chat, node_name, agent_run: run)
    end

    def clear_progress!(run)
      ProgressBroadcaster.clear!(run.chat)
    end

    def request_approval!(run)
      ApprovalBroadcaster.request!(run.reload)
    end
  end
end
