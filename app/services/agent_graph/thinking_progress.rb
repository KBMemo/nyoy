# frozen_string_literal: true

module AgentGraph
  # Throttled live thinking updates for the research progress panel.
  class ThinkingProgress
    BROADCAST_INTERVAL = 1.0

    def initialize(chat)
      @chat = chat
      @last_at = nil
      @last_text = nil
    end

    def push(text)
      body = text.to_s
      return if body.empty?
      return unless due?

      @last_at = now
      @last_text = body
      ProgressBroadcaster.thinking!(@chat, body)
    end

    def flush(text)
      body = text.to_s
      return if body.empty?
      return if body == @last_text

      @last_text = body
      ProgressBroadcaster.thinking!(@chat, body)
    end

    private

    def due?
      @last_at.nil? || (now - @last_at) >= BROADCAST_INTERVAL
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
