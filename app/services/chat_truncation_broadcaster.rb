# frozen_string_literal: true

class ChatTruncationBroadcaster
  ERROR_PREFIX = ChatErrorBroadcaster::ERROR_PREFIX

  def self.call(chat)
    new(chat).call
  end

  def initialize(chat)
    @chat = chat
  end

  def call
    @chat.reload
    body = ChatTruncationAdvice.message_for(@chat)
    message = @chat.messages.create!(role: :assistant, content: "#{ERROR_PREFIX}#{body}")
    ChatUiBroadcaster.message_upsert(message)
    message
  end
end
