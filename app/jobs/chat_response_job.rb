class ChatResponseJob < ApplicationJob
  def perform(chat_id)
    chat = Chat.find(chat_id)

    # Cancelled before the job even started streaming: still surface a "中止し
    # ました" message so the user's turn does not sit there unanswered. finish!
    # and the form reset are handled by the ensure block below.
    if chat.response_state == ChatResponseControl::STATES[:cancelled]
      ChatCancellationBroadcaster.call(chat)
      return
    end

    timer = ChatResponseTimer.new
    stream_state = StreamState.new
    message = nil

    chat.complete do |chunk|
      timer.observe_chunk!(chunk)

      previous = message
      message = current_assistant_message(chat, previous)
      next unless message

      # A tool round starts a fresh assistant message; flush the previous one
      # so its final streamed text is not left half-rendered.
      if previous && previous.id != message.id
        stream_state.flush(previous)
        persist_streamed_state!(previous, stream_state)
        broadcast_assistant_message!(previous, stream_state: stream_state)
      end

      thinking_text = chunk.thinking&.text
      if streamable_text?(thinking_text)
        stream_state.append_thinking_for(message, thinking_text)
        stream_state.broadcast_thinking(message)
      end

      next unless streamable_text?(chunk.content)

      stream_state.append_for(message, chunk.content)
      stream_state.broadcast_content(message)
    end

    message = current_assistant_message(chat, message) if message
    stream_state.flush(message) if message
    persist_streamed_state!(message, stream_state) if message
    persist_assistant_timing(chat, timer)
    broadcast_assistant_message!(message, stream_state: stream_state) if message
  rescue ChatResponseControl::Cancelled
    finalize_cancellation(chat, message, stream_state)
  rescue StandardError => e
    # Everything here is turned into a friendly chat bubble, so log the real
    # error (including genuine bugs like NoMethodError) before it is hidden.
    Rails.logger.error("ChatResponseJob failed for chat=#{chat_id}: #{e.full_message}")
    ChatErrorBroadcaster.fail!(chat, e)
  ensure
    ChatResponseControl.finish!(chat)
    broadcast_form_reset(chat)
  end

  private

  # Cancelled mid-stream. RubyLLM only persists the body on completion, so the
  # partial answer lives in stream_state, not the DB. Keep it visible (marked as
  # interrupted) rather than dropping it; fall back to a plain "中止しました"
  # bubble when nothing meaningful was produced yet.
  def finalize_cancellation(chat, message, stream_state)
    partial = message && stream_state.text_for(message)

    if message && partial.present?
      thinking = stream_state.thinking_for(message).presence
      message.update_columns(
        content: partial,
        thinking_text: thinking,
        cancelled: true,
        updated_at: Time.current
      )
      message.assign_attributes(content: partial, thinking_text: thinking, cancelled: true)
      broadcast_assistant_message!(message, stream_state: stream_state)
    else
      ChatCancellationBroadcaster.call(chat)
    end
  end

  # Resolves the assistant message being streamed with a lightweight id lookup,
  # reusing the cached record until a new assistant message appears (tool round).
  def current_assistant_message(chat, cached)
    latest_id = chat.messages.where(role: :assistant).order(id: :desc).limit(1).pick(:id)
    return cached if latest_id.nil?
    return cached if cached && cached.id == latest_id

    Message.find(latest_id)
  end

  def persist_streamed_state!(message, stream_state)
    return unless message

    content = stream_state.text_for(message)
    thinking = stream_state.thinking_for(message)

    attrs = {}
    attrs[:content] = content if streamable_text?(content)
    attrs[:thinking_text] = thinking if streamable_text?(thinking)
    return if attrs.empty?

    message.update_columns(attrs.merge(updated_at: Time.current))
    message.assign_attributes(attrs)
  end

  def broadcast_assistant_message!(message, stream_state: nil)
    return unless message

    message.reload
    content = stream_state&.text_for(message)
    content = message.content unless streamable_text?(content)
    thinking = stream_state&.thinking_for(message)
    thinking = message.thinking_text unless streamable_text?(thinking)

    message.broadcast_rendered_content!(content) if streamable_text?(content)
    message.broadcast_rendered_thinking!(thinking) if streamable_text?(thinking)
    message.broadcast_refresh!(content: content, thinking_text: thinking)
  end

  # Newline-only chunks are blank? in Rails but must still be streamed and saved.
  def streamable_text?(text)
    !text.nil? && text != ""
  end

  def persist_assistant_timing(chat, timer)
    assistant_message = chat.messages.where(role: :assistant).order(:id).last
    return unless assistant_message

    attrs = timer.message_timing_attributes(context_build_elapsed_ms: chat.context_build_elapsed_ms)
    return if attrs.empty?

    # Timing-only writes must not re-render the whole message bubble; that would
    # replace streamed markdown with a stale DB snapshot and look truncated.
    assistant_message.update_columns(attrs.merge(updated_at: Time.current))
  end

  def broadcast_form_reset(chat)
    chat.reload
    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{chat.id}",
      target: "new_message",
      html: MessagesController.render(
        partial: "messages/form",
        locals: {
          chat: chat,
          message: Message.new,
          form_url: Rails.application.routes.url_helpers.chat_messages_path(chat)
        }
      )
    )
  end

  class StreamState
    # Coalesce Turbo broadcasts so a burst of chunks re-renders at most this
    # often (seconds). Re-rendering the whole accumulated markdown per chunk is
    # O(n^2) work and floods ActionCable.
    BROADCAST_INTERVAL = 0.12

    def initialize
      @text_by_message_id = {}
      @thinking_by_message_id = {}
      @current_message_id = nil
      @current_thinking_message_id = nil
      @content_broadcast_at = {}
      @thinking_broadcast_at = {}
    end

    def append_for(message, chunk)
      if @current_message_id != message.id
        @current_message_id = message.id
        @text_by_message_id[message.id] = +""
      end

      @text_by_message_id[message.id] << chunk
    end

    def append_thinking_for(message, chunk)
      if @current_thinking_message_id != message.id
        @current_thinking_message_id = message.id
        @thinking_by_message_id[message.id] = +""
      end

      @thinking_by_message_id[message.id] << chunk
    end

    def text_for(message)
      @text_by_message_id.fetch(message.id, +"")
    end

    def thinking_for(message)
      @thinking_by_message_id.fetch(message.id, +"")
    end

    def broadcast_content(message, force: false)
      return if text_for(message).empty?
      return unless due?(@content_broadcast_at, message.id, force)

      @content_broadcast_at[message.id] = now
      message.broadcast_rendered_content!(text_for(message))
    end

    def broadcast_thinking(message, force: false)
      return if thinking_for(message).empty?
      return unless due?(@thinking_broadcast_at, message.id, force)

      @thinking_broadcast_at[message.id] = now
      message.broadcast_rendered_thinking!(thinking_for(message))
    end

    # Emit the final state for a message, bypassing the debounce interval.
    def flush(message)
      return unless message

      broadcast_content(message, force: true)
      broadcast_thinking(message, force: true)
    end

    private

    def due?(timestamps, message_id, force)
      return true if force

      last = timestamps[message_id]
      last.nil? || (now - last) >= BROADCAST_INTERVAL
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end