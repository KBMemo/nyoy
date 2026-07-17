# frozen_string_literal: true

module AgentGraph
  module RoleServices
    DEFAULTS = {
      final_answer: -> { AgentGraph::RoleServices::FinalAnswer.new }
    }.freeze

    class << self
      def register(role, service)
        registry[normalize(role)] = service
      end

      def fetch(role)
        key = normalize(role)
        registry.fetch(key) { default_for(key) }
      end

      def with(role, service)
        key = normalize(role)
        previous = registry.fetch(key, :__missing__)
        register(key, service)
        yield
      ensure
        if previous == :__missing__
          registry.delete(key)
        else
          registry[key] = previous
        end
      end

      def reset!
        @registry = {}
      end

      private

      def registry
        @registry ||= {}
      end

      def normalize(role)
        role.to_sym
      end

      def default_for(role)
        factory = DEFAULTS.fetch(role) do
          raise KeyError, "unknown AgentGraph role service: #{role}"
        end
        factory.call
      end
    end

    class FinalAnswer
      def call(state:, run:, chat:)
        AgentGraph::FinalAnswerSynthesizer.new(chat).call(state)
      end
    end
  end
end
