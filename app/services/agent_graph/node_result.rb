# frozen_string_literal: true

module AgentGraph
  class NodeResult
    attr_reader :updates, :goto, :interrupt, :error

    def self.next(goto = nil, updates: {})
      new(updates: updates, goto: goto, explicit_goto: !goto.nil?)
    end

    def self.end(updates: {})
      new(updates: updates, goto: nil, explicit_goto: true)
    end

    def self.interrupt(updates: {})
      new(updates: updates, interrupt: true)
    end

    def self.fail(message, updates: {})
      new(updates: updates, error: message)
    end

    def initialize(updates: {}, goto: nil, interrupt: false, error: nil, explicit_goto: false)
      @updates = (updates || {}).deep_stringify_keys
      @goto = goto
      @interrupt = interrupt
      @error = error
      @explicit_goto = explicit_goto
    end

    def interrupt?
      @interrupt
    end

    def failed?
      @error.present?
    end

    def explicit_goto?
      @explicit_goto
    end

    def finished?
      explicit_goto? && @goto.nil? && !interrupt? && !failed?
    end
  end
end
