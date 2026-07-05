class ChatResponseJob < ApplicationJob
  def perform(chat_id)
    chat = Chat.find(chat_id)
    return ChatResponseControl.finish!(chat) if chat.response_state == ChatResponseControl::STATES[:cancelled]

    timer = ChatResponseTimer.new
    stream_state = StreamState.new

    chat.complete do |chunk|
      timer.observe_chunk!(chunk)

      message = chat.messages.where(role: :assistant).order(:id).last
      next unless message

      if chunk.thinking&.text.present?
        stream_state.append_thinking_for(message, chunk.thinking.text)
        message.broadcast_rendered_thinking!(stream_state.thinking_for(message))
      end

      next unless chunk.content.present?

      stream_state.append_for(message, chunk.content)
      message.broadcast_rendered_content!(stream_state.text_for(message))
    end

    persist_assistant_timing(chat, timer)
  rescue ChatResponseControl::Cancelled
    ChatCancellationBroadcaster.call(chat)
  rescue RubyLLM::Error, StandardError => e
    ChatErrorBroadcaster.fail!(chat, e)
  ensure
    ChatResponseControl.finish!(chat)
    broadcast_form_reset(chat)
  end

  private

  def persist_assistant_timing(chat, timer)
    assistant_message = chat.messages.where(role: :assistant).order(:id).last
    return unless assistant_message

    assistant_message.update!(
      timer.message_timing_attributes(context_build_elapsed_ms: chat.context_build_elapsed_ms)
    )
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
    def initialize
      @text_by_message_id = {}
      @thinking_by_message_id = {}
      @current_message_id = nil
      @current_thinking_message_id = nil
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
  end
end