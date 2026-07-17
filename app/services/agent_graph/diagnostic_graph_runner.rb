# frozen_string_literal: true

module AgentGraph
  class DiagnosticGraphRunner
    def self.call(chat, note: nil)
      new(chat, note: note).call
    end

    def self.resume(agent_run, decision:)
      raise ArgumentError, "Diagnostic Graph approval resume is not supported"
    end

    def initialize(chat, note: nil)
      @chat = chat
      @note = note
    end

    def call
      RunLauncher.for_graph(
        chat: @chat,
        graph_name: DiagnosticGraph::NAME,
        state: DiagnosticInitialState.build(
          chat: @chat,
          note: @note
        )
      )
    end
  end
end
