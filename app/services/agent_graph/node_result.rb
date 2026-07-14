# frozen_string_literal: true

module AgentGraph
  class NodeResult
    attr_reader :updates, :goto, :interrupt, :error

    def self.next(goto, updates: {})
      new(updates: updates, goto: goto)
    end

    def self.end(updates: {})
      new(updates: updates, goto: nil)
    end

    def self.interrupt(updates: {})
      new(updates: updates, interrupt: true)
    end

    def self.fail(message, updates: {})
      new(updates: updates, error: message)
    end

    def initialize(updates: {}, goto: nil, interrupt: false, error: nil)
      @updates = (updates || {}).deep_stringify_keys
      @goto = goto
      @interrupt = interrupt
      @error = error
    end

    def interrupt?
      @interrupt
    end

    def failed?
      @error.present?
    end

    def finished?
      @goto.nil? && !interrupt? && !failed?
    end
  end
end
