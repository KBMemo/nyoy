# frozen_string_literal: true

module AgentGraph
  module Core
    class Runner
      MAX_STEPS = 12

      def initialize(graph:, context:)
        @graph = graph
        @context = ContextProtocol.validate!(context)
      end

      def call
        @context.validate_graph!
        @context.start_run!

        MAX_STEPS.times do
          @context.check_cancelled!

          node_name = @context.current_node
          break @context.finish_completed! if empty_node_name?(node_name)

          result = execute_node(node_name)
          @context.apply_result!(node_name, result)

          break @context.finish_failed!(result.error) if result.failed?
          break @context.interrupt!(node_name) if result.interrupt?
          break @context.finish_completed! if result.finished?

          @context.update_current_node!(next_node_for(node_name, result))
        end

        @context.finish_failed!("max steps exceeded (#{MAX_STEPS})") if @context.running?
        @context.result
      rescue Cancelled
        @context.finish_cancelled!
        raise
      rescue StandardError => e
        if @context.cancelled_exception?(e)
          @context.finish_cancelled!
          raise Cancelled
        end

        @context.finish_failed!(e.message)
        raise
      end

      private

      def execute_node(node_name)
        node = @graph.node_for(node_name)
        raise "unknown node: #{node_name}" unless node

        @context.node_started!(node_name)

        node_run = @context.create_node_run!(node_name: node_name, input_state: @context.state)
        result = @context.invoke_node(node, state: deep_dup(@context.state))
        @context.complete_node_run!(node_run, result: result)

        result
      rescue StandardError => e
        @context.fail_node_run!(node_run, message: e.message)
        raise Cancelled if @context.cancelled_exception?(e)

        NodeResult.fail(e.message)
      end

      def next_node_for(node_name, result)
        return result.goto if result.explicit_goto?

        @graph.next_node_for(node_name, @context.state)
      end

      def empty_node_name?(node_name)
        node_name.nil? || (node_name.respond_to?(:empty?) && node_name.empty?)
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), copy|
            copy[deep_dup(key)] = deep_dup(item)
          end
        when Array
          value.map { |item| deep_dup(item) }
        else
          value.dup
        end
      rescue TypeError
        value
      end
    end
  end
end
