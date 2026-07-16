# frozen_string_literal: true

class ChatResponseTimer
  def initialize
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @thinking_started_at = nil
    @thinking_elapsed_ms = nil
    @first_chunk_elapsed_ms = nil
    @usage_attributes = {}
  end

  def observe_chunk!(chunk)
    observe_first_chunk!(chunk)
    observe_usage!(chunk)

    if thinking_chunk?(chunk)
      @thinking_started_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elsif chunk.content.present? && @thinking_started_at && @thinking_elapsed_ms.nil?
      @thinking_elapsed_ms = elapsed_ms(@thinking_started_at)
    end
  end

  # Elapsed time to the caller-supplied context build (Chat#to_llm) plus HTTP setup, in ms.
  def message_timing_attributes(context_build_elapsed_ms: nil)
    ended_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    attrs = { response_elapsed_ms: elapsed_ms(@started_at, ended_at) }

    thinking_ms = @thinking_elapsed_ms
    thinking_ms ||= elapsed_ms(@thinking_started_at, ended_at) if @thinking_started_at
    attrs[:thinking_elapsed_ms] = thinking_ms if thinking_ms

    attrs[:first_chunk_elapsed_ms] = @first_chunk_elapsed_ms if @first_chunk_elapsed_ms
    attrs[:context_build_elapsed_ms] = context_build_elapsed_ms.round if context_build_elapsed_ms
    attrs.merge!(@usage_attributes)

    attrs
  end

  private

  def observe_first_chunk!(chunk)
    return unless @first_chunk_elapsed_ms.nil?
    return unless chunk.content.present? || thinking_chunk?(chunk)

    @first_chunk_elapsed_ms = elapsed_ms(@started_at)
  end

  def thinking_chunk?(chunk)
    chunk.thinking&.text.present?
  end

  def observe_usage!(chunk)
    attrs = ChatUsageAttributes.from(chunk)
    @usage_attributes.merge!(attrs) if attrs.present?
  end

  def elapsed_ms(from, to = Process.clock_gettime(Process::CLOCK_MONOTONIC))
    ((to - from) * 1000).round
  end
end
