# frozen_string_literal: true

module AgentGraph
  class Runner
    MAX_STEPS = 12

    def initialize(agent_run, graph:)
      @run = agent_run
      @graph = graph
    end

    def call
      @run.update!(
        status: "running",
        started_at: @run.started_at || Time.current,
        current_node: @run.current_node.presence || @graph.start_node
      )

      MAX_STEPS.times do
        ChatResponseControl.check!(@run.chat_id)

        node_name = @run.current_node
        break finish_completed! if node_name.blank?

        result = execute_node(node_name)
        apply_result!(node_name, result)

        break finish_failed!(result.error) if result.failed?
        break interrupt!(node_name) if result.interrupt?
        break finish_completed! if result.finished?

        @run.update!(current_node: result.goto)
      end

      finish_failed!("max steps exceeded (#{MAX_STEPS})") if @run.running?
      @run
    rescue ChatResponseControl::Cancelled
      ProgressBroadcaster.clear!(@run.chat)
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

      ProgressBroadcaster.started!(@run.chat, node_name)

      node_run = @run.agent_node_runs.create!(
        node_name: node_name,
        status: "running",
        input_snapshot: @run.state,
        started_at: Time.current
      )

      result = node.call(state: @run.state.deep_dup, run: @run, chat: @run.chat)

      node_run.update!(
        status: result.failed? ? "failed" : "completed",
        output_snapshot: {
          updates: result.updates,
          goto: result.goto,
          interrupt: result.interrupt?,
          error: result.error
        }.compact,
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
      merged = (@run.state || {}).deep_merge(result.updates)
      @run.update!(state: merged)
      @run.agent_checkpoints.create!(node_name: node_name, state: merged)
    end

    def finish_completed!
      ProgressBroadcaster.clear!(@run.chat)
      @run.update!(
        status: "completed",
        current_node: nil,
        finished_at: Time.current
      )
    end

    def interrupt!(node_name)
      # Approval panel replaces the progress line.
      ProgressBroadcaster.clear!(@run.chat)
      @run.update!(
        status: "awaiting_approval",
        current_node: node_name,
        finished_at: nil
      )
      ApprovalBroadcaster.request!(@run.reload)
    end

    def finish_failed!(message)
      ProgressBroadcaster.clear!(@run.chat)
      @run.update!(
        status: "failed",
        error_message: message.to_s,
        finished_at: Time.current
      )
      @run
    end
  end
end
