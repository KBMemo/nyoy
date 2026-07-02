class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments

  broadcasts_to ->(message) { "chat_#{message.chat_id}" }, inserts_by: :append

  def chat_error?
    role.to_s == "assistant" && content.to_s.start_with?(ChatErrorBroadcaster::ERROR_PREFIX)
  end

  def chat_error_message
    content.to_s.delete_prefix(ChatErrorBroadcaster::ERROR_PREFIX)
  end

  def to_partial_path
    return "messages/chat_error" if chat_error?

    super
  end

  def broadcast_append_chunk(content)
    broadcast_append_to "chat_#{chat_id}",
      target: "message_#{id}_content",
      content: ERB::Util.html_escape(content.to_s)
  end
end
