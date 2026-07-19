# frozen_string_literal: true

module AgentGraph
  module Core
    module ContextProtocol
      REQUIRED_METHODS = %i[
        validate_graph!
        start_run!
        result
        check_cancelled!
        current_node
        running?
        update_current_node!
        node_started!
        create_node_run!
        complete_node_run!
        fail_node_run!
        state
        apply_result!
        invoke_node
        finish_completed!
        finish_failed!
        finish_cancelled!
        interrupt!
        cancelled_exception?
      ].freeze

      def self.validate!(context)
        missing = REQUIRED_METHODS.reject { |method_name| context.respond_to?(method_name) }
        return context if missing.empty?

        raise ArgumentError, "invalid AgentGraph context; missing methods: #{missing.join(", ")}"
      end
    end
  end
end
