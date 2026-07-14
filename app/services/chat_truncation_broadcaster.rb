# frozen_string_literal: true

class ChatTruncationBroadcaster
  ERROR_PREFIX = ChatErrorBroadcaster::ERROR_PREFIX

  MESSAGE = <<~TEXT.strip
    生成上限（max_tokens）に達したため応答を打ち切りました。
    チャット設定で max_tokens を増やすか、質問を短くしてください。
  TEXT

  def self.call(chat)
    new(chat).call
  end

  def initialize(chat)
    @chat = chat
  end

  def call
    @chat.reload
    message = @chat.messages.create!(role: :assistant, content: "#{ERROR_PREFIX}#{MESSAGE}")
    ChatUiBroadcaster.message_upsert(message)
    message
  end
end
