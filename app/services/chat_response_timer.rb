# frozen_string_literal: true

class ChatResponseTimer
  def initialize
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @thinking_started_at = nil
    @thinking_elapsed_ms = nil
  end

  def observe_chunk!(chunk)
    if thinking_chunk?(chunk)
      @thinking_started_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elsif chunk.content.present? && @thinking_started_at && @thinking_elapsed_ms.nil?
      @thinking_elapsed_ms = elapsed_ms(@thinking_started_at)
    end
  end

  def message_timing_attributes
    ended_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    attrs = { response_elapsed_ms: elapsed_ms(@started_at, ended_at) }

    thinking_ms = @thinking_elapsed_ms
    thinking_ms ||= elapsed_ms(@thinking_started_at, ended_at) if @thinking_started_at
    attrs[:thinking_elapsed_ms] = thinking_ms if thinking_ms

    attrs
  end

  private

  def thinking_chunk?(chunk)
    chunk.thinking&.text.present?
  end

  def elapsed_ms(from, to = Process.clock_gettime(Process::CLOCK_MONOTONIC))
    ((to - from) * 1000).round
  end
end
