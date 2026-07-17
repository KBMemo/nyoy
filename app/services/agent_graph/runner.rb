# frozen_string_literal: true

module AgentGraph
  class Runner
    MAX_STEPS = 12

    def initialize(agent_run, graph:, context: nil)
      @run = agent_run
      @graph = graph
      @context = context || RuntimeContext.new(run: agent_run, graph: graph)
    end

    def call
      raise ArgumentError, "agent run graph mismatch: #{@run.graph_name} != #{@graph.name}" if @run.graph_name != @graph.name

      @run.update!(
        status: "running",
        started_at: @run.started_at || Time.current,
        current_node: @run.current_node.presence || @graph.start_node
      )

      MAX_STEPS.times do
        @context.check_cancelled!

        node_name = @run.current_node
        break finish_completed! if node_name.blank?

        result = execute_node(node_name)
        apply_result!(node_name, result)

        break finish_failed!(result.error) if result.failed?
        break interrupt!(node_name) if result.interrupt?
        break finish_completed! if result.finished?

        @run.update!(current_node: next_node_for(node_name, result))
      end

      finish_failed!("max steps exceeded (#{MAX_STEPS})") if @run.running?
      @run
    rescue ChatResponseControl::Cancelled
      @context.clear_progress!
      @run.update!(status: "cancelled", finished_at: Time.current, error_message: "cancelled")
      raise
    rescue StandardError => e
      finish_failed!(e.message)
      raise
    end

    private

    def execute_node(node_name)
      node = @graph.node_for(node_name)
      raise "unknown node: #{node_name}" unless node

      @context.node_started!(node_name)

      node_run = @run.agent_node_runs.create!(
        node_name: node_name,
        status: "running",
        input_snapshot: scrub_null_bytes(@run.state),
        started_at: Time.current
      )

      result = node.call(**@context.node_call_kwargs(state: @run.state.deep_dup))

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

      result
    rescue StandardError => e
      node_run&.update!(
        status: "failed",
        error_message: e.message,
        finished_at: Time.current
      )
      NodeResult.fail(e.message)
    end

    def apply_result!(node_name, result)
      merged = scrub_null_bytes((@run.state || {}).deep_merge(result.updates))
      @run.update!(state: merged)
      @run.agent_checkpoints.create!(node_name: node_name, state: merged)
    end

    def next_node_for(node_name, result)
      return result.goto if result.explicit_goto?

      @graph.next_node_for(node_name, @run.state)
    end

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

    def finish_completed!
      @context.clear_progress!
      @run.update!(
        status: "completed",
        current_node: nil,
        finished_at: Time.current
      )
    end

    def interrupt!(node_name)
      # Approval panel replaces the progress line.
      @context.clear_progress!
      @run.update!(
        status: "awaiting_approval",
        current_node: node_name,
        finished_at: nil
      )
      @context.request_approval!
    end

    def finish_failed!(message)
      @context.clear_progress!
      @run.update!(
        status: "failed",
        error_message: message.to_s,
        finished_at: Time.current
      )
      @run
    end
  end
end
