# frozen_string_literal: true

module AgentGraph
  module RoleServices
    DEFAULTS = {
      draft: -> { AgentGraph::RoleServices::EvidencePackDraft.new },
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

    class EvidencePackDraft
      def call(state:, run:, chat:)
        synthesizer = AgentGraph::EvidenceSynthesizer.new(chat)
        evidence = synthesizer.evidence_pack(state)
        draft = synthesizer.fallback_answer(evidence)
        [
          draft,
          false,
          {
            "source" => "evidence_pack",
            "model_id" => nil,
            "thinking" => nil,
            "evidence" => evidence_counts(evidence)
          }
        ]
      end

      private

      def evidence_counts(evidence)
        {
          "memo" => evidence[:memo].to_s.empty? ? 0 : 1,
          "search_results" => Array(evidence[:search_results]).sum { |payload| Array(payload["results"]).size },
          "fetched_pages" => Array(evidence[:fetched_pages]).size,
          "errors" => Array(evidence[:errors]).size
        }
      end
    end
  end
end
