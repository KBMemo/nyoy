# frozen_string_literal: true

module AgentGraph
  class ActiveRecordRunStore
    attr_reader :run, :graph

    def initialize(run:, graph:)
      @run = run
      @graph = graph
    end

    def validate_graph!
      return if run.graph_name == graph.name

      raise ArgumentError, "agent run graph mismatch: #{run.graph_name} != #{graph.name}"
    end

    def result
      run
    end

    def start_run!
      run.update!(
        status: "running",
        started_at: run.started_at || Time.current,
        current_node: run.current_node.presence || graph.start_node
      )
    end

    def current_node
      run.current_node
    end

    def running?
      run.running?
    end

    def update_current_node!(node_name)
      run.update!(current_node: node_name)
    end

    def create_node_run!(node_name:, input_state:)
      run.agent_node_runs.create!(
        node_name: node_name,
        status: "running",
        input_snapshot: scrub_null_bytes(input_state),
        started_at: Time.current
      )
    end

    def complete_node_run!(node_run, result:)
      node_run.update!(
        status: result.failed? ? "failed" : "completed",
        output_snapshot: scrub_null_bytes({
          updates: result.updates,
          goto: result.goto,
          interrupt: result.interrupt?,
          error: result.error
        }.compact),
        error_message: result.error,
        finished_at: Time.current
      )
    end

    def fail_node_run!(node_run, message:)
      node_run&.update!(
        status: "failed",
        error_message: message.to_s,
        finished_at: Time.current
      )
    end

    def state
      run.state || {}
    end

    def apply_result!(node_name, result)
      merged = scrub_null_bytes(state.deep_merge(result.updates))
      run.update!(state: merged)
      run.agent_checkpoints.create!(node_name: node_name, state: merged)
    end

    def finish_completed!
      run.update!(
        status: "completed",
        current_node: nil,
        finished_at: Time.current
      )
    end

    def interrupt!(node_name)
      run.update!(
        status: "awaiting_approval",
        current_node: node_name,
        finished_at: nil
      )
    end

    def finish_failed!(message)
      run.update!(
        status: "failed",
        error_message: message.to_s,
        finished_at: Time.current
      )
      run
    end

    def finish_cancelled!
      run.update!(status: "cancelled", finished_at: Time.current, error_message: "cancelled")
    end

    private

    def scrub_null_bytes(value)
      case value
      when Hash
        value.transform_values { |item| scrub_null_bytes(item) }
      when Array
        value.map { |item| scrub_null_bytes(item) }
      when String
        value.delete("\u0000")
      else
        value
      end
    end
  end
end
