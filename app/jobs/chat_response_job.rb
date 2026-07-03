class ChatResponseJob < ApplicationJob
  def perform(chat_id)
    chat = Chat.find(chat_id)
    timer = ChatResponseTimer.new
    stream_state = StreamState.new

    chat.complete do |chunk|
      timer.observe_chunk!(chunk)
      next unless chunk.content.present?

      message = chat.messages.where(role: :assistant).order(:id).last
      next unless message

      stream_state.append_for(message, chunk.content)
      message.broadcast_rendered_content!(stream_state.text_for(message))
    end

    persist_assistant_timing(chat, timer)
  rescue RubyLLM::Error, StandardError => e
    ChatErrorBroadcaster.fail!(chat, e)
  end

  private

  def persist_assistant_timing(chat, timer)
    assistant_message = chat.messages.where(role: :assistant).order(:id).last
    return unless assistant_message

    assistant_message.update!(timer.message_timing_attributes)
  end

  class StreamState
    def initialize
      @text_by_message_id = {}
      @current_message_id = nil
    end

    def append_for(message, chunk)
      if @current_message_id != message.id
        @current_message_id = message.id
        @text_by_message_id[message.id] = +""
      end

      @text_by_message_id[message.id] << chunk
    end

    def text_for(message)
      @text_by_message_id.fetch(message.id, +"")
    end
  end
end
