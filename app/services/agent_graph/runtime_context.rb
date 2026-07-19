# frozen_string_literal: true

module AgentGraph
  class RuntimeContext
    attr_reader :store

    def initialize(run:, graph:, store: nil)
      @store = store || ActiveRecordRunStore.new(run: run, graph: graph)
    end

    def run
      store.run
    end

    def graph
      store.graph
    end

    def chat
      run.chat
    end

    def start_run!
      store.start_run!
    end

    def current_node
      store.current_node
    end

    def running?
      store.running?
    end

    def update_current_node!(node_name)
      store.update_current_node!(node_name)
    end

    def check_cancelled!
      ChatResponseControl.check!(run.chat_id)
    end

    def node_started!(node_name)
      ProgressBroadcaster.started!(chat, node_name, agent_run: run)
    end

    def create_node_run!(node_name:, input_state:)
      store.create_node_run!(node_name: node_name, input_state: input_state)
    end

    def complete_node_run!(node_run, result:)
      store.complete_node_run!(node_run, result: result)
    end

    def fail_node_run!(node_run, message:)
      store.fail_node_run!(node_run, message: message)
    end

    def state
      store.state
    end

    def apply_result!(node_name, result)
      store.apply_result!(node_name, result)
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

    def finish_completed!
      clear_progress!
      store.finish_completed!
    end

    def interrupt!(node_name)
      clear_progress!
      store.interrupt!(node_name)
      request_approval!
    end

    def finish_failed!(message)
      clear_progress!
      store.finish_failed!(message)
    end

    def finish_cancelled!
      clear_progress!
      store.finish_cancelled!
    end
  end
end
