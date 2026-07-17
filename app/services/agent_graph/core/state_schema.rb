# frozen_string_literal: true

module AgentGraph
  module Core
    class StateSchema
      def initialize(name:, required_keys:)
        @name = name
        @required_keys = required_keys.map(&:to_s).freeze
      end

      def validate!(state)
        missing = @required_keys - state.keys.map(&:to_s)
        return state if missing.empty?

        raise ArgumentError, "#{@name} state missing keys: #{missing.join(", ")}"
      end
    end
  end
end
