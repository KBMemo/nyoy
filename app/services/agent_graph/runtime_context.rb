# frozen_string_literal: true

module AgentGraph
  class RuntimeContext
    attr_reader :run, :graph

    def initialize(run:, graph:)
      @run = run
      @graph = graph
    end

    def chat
      run.chat
    end

    def check_cancelled!
      ChatResponseControl.check!(run.chat_id)
    end

    def node_started!(node_name)
      ProgressBroadcaster.started!(chat, node_name, agent_run: run)
    end

    def clear_progress!
      ProgressBroadcaster.clear!(chat)
    end

    def request_approval!
      ApprovalBroadcaster.request!(run.reload)
    end

    def node_call_kwargs(state:)
      {
        state: state,
        run: run,
        chat: chat
      }
    end
  end
end
