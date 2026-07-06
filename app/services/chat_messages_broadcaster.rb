# frozen_string_literal: true

class ChatMessagesBroadcaster
  def self.sync!(chat)
    new(chat).sync!
  end

  def initialize(chat)
    @chat = chat
  end

  def sync!
    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{@chat.id}",
      target: "messages",
      partial: "chats/messages",
      locals: { chat: @chat.reload }
    )
  end
end
