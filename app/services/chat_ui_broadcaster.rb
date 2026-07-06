# frozen_string_literal: true

class ChatUiBroadcaster
  class << self
    def message_upsert(message)
      broadcast(message.chat, {
        type: "message_upsert",
        message_id: message.id,
        html: render_message(message)
      })
    end

    def message_removed(message)
      broadcast(message.chat, {
        type: "message_removed",
        message_id: message.id
      })
    end

    def assistant_content(message, text, seq:)
      broadcast(message.chat, {
        type: "assistant_content",
        message_id: message.id,
        seq: seq,
        text: text.to_s
      })
    end

    def assistant_thinking(message, text, seq:)
      broadcast(message.chat, {
        type: "assistant_thinking",
        message_id: message.id,
        seq: seq,
        text: text.to_s
      })
    end

    def assistant_finalized(message, content:, thinking_text:, seq:)
      broadcast(message.chat, {
        type: "assistant_finalized",
        message_id: message.id,
        seq: seq,
        html: render_message(message, content: content, thinking_text: thinking_text)
      })
    end

    def form_updated(chat)
      chat.reload
      broadcast(chat, {
        type: "form_updated",
        html: MessagesController.render(
          partial: "messages/form",
          locals: {
            chat: chat,
            message: Message.new,
            form_url: Rails.application.routes.url_helpers.chat_messages_path(chat)
          }
        )
      })
    end

    private

    def broadcast(chat, payload)
      ChatChannel.broadcast_to(chat, payload)
    end

    def render_message(message, locals = {})
      ApplicationController.render(
        partial: message.to_partial_path,
        locals: {
          message: message,
          assistant: message,
          user: message,
          system: message,
          tool: message
        }.merge(locals)
      )
    end
  end
end
