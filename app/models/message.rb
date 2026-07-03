class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments

  after_create_commit :broadcast_message_created
  after_update_commit :broadcast_message_updated
  after_destroy_commit :broadcast_message_removed

  def to_llm
    return super unless user_message_with_attachments?

    RubyLLM::Message.new(
      role: :user,
      content: llm_text_with_attachment_hint,
      tool_calls: {},
      tool_call_id: nil,
      model_id: model_association&.model_id
    )
  end

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

  def broadcast_rendered_content!(text = nil)
    broadcast_replace_to(
      "chat_#{chat_id}",
      target: "message_#{id}_content",
      html: ChatMarkdownRenderer.render(text || content)
    )
  end

  private

  def broadcast_message_created
    broadcast_append_to(
      "chat_#{chat_id}",
      target: "messages",
      partial: to_partial_path,
      locals: message_locals
    )
  end

  def broadcast_message_updated
    broadcast_replace_to(
      "chat_#{chat_id}",
      target: "message_#{id}",
      partial: to_partial_path,
      locals: message_locals
    )
  end

  def broadcast_message_removed
    broadcast_remove_to("chat_#{chat_id}")
  end

  def message_locals
    { message: self, assistant: self, user: self, system: self, tool: self }
  end

  def user_message_with_attachments?
    role.to_s == "user" && attachments.attached?
  end

  def llm_text_with_attachment_hint
    text = content.to_s.strip
    text = "" if ChatImageAttachments.placeholder?(text)
    hint = ChatImageAttachments.llm_attachment_notice(attachments.count)
    [text, hint].reject(&:blank?).join("\n\n")
  end
end
