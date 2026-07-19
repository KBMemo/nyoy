# frozen_string_literal: true

module AgentGraph
  class RuntimeContext
    attr_reader :store, :signals

    def initialize(run:, graph:, store: nil, signals: nil)
      @store = store || ActiveRecordRunStore.new(run: run, graph: graph)
      @signals = signals || RailsRuntimeSignals.new
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
      signals.check_cancelled!(run)
    end

    def cancelled_exception?(error)
      error.is_a?(Cancelled) || signals.cancelled_exception?(error)
    end

    def node_started!(node_name)
      signals.node_started!(run, node_name)
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
      signals.clear_progress!(run)
    end

    def request_approval!
      signals.request_approval!(run)
    end

    def node_call_kwargs(state:)
      store.node_call_kwargs(state: state)
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

    private

    def run
      store.run
    end
  end
end
