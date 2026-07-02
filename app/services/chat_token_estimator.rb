# frozen_string_literal: true

class ChatTokenEstimator
  CHARS_PER_TOKEN = 4.0

  def self.estimate_text(text)
    (text.to_s.bytesize / CHARS_PER_TOKEN).ceil
  end

  def self.estimate_messages(messages)
    Array(messages).sum { |message| estimate_text(message_content(message)) }
  end

  def self.message_content(message)
    message.respond_to?(:content) ? message.content.to_s : message.to_s
  end
end
