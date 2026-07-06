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

  def chat_cancelled?
    role.to_s == "assistant" && content.to_s.start_with?(ChatCancellationBroadcaster::CANCELLED_PREFIX)
  end

  def chat_error_message
    content.to_s.delete_prefix(ChatErrorBroadcaster::ERROR_PREFIX)
  end

  def chat_cancelled_message
    content.to_s.delete_prefix(ChatCancellationBroadcaster::CANCELLED_PREFIX)
  end

  def to_partial_path
    return "messages/chat_error" if chat_error?
    return "messages/chat_cancelled" if chat_cancelled?

    super
  end

  def broadcast_rendered_content!(text = nil)
    broadcast_replace_to(
      "chat_#{chat_id}",
      target: "message_#{id}_content",
      html: ChatMarkdownRenderer.render(text || content)
    )
  end

  def broadcast_rendered_thinking!(text)
    broadcast_replace_to(
      "chat_#{chat_id}",
      target: "message_#{id}_thinking_section",
      partial: "messages/thinking_section",
      locals: { message: self, text: text }
    )
  end

  # Explicit full-bubble refresh used when a streaming turn finishes. While the
  # chat is responding?, after_update_commit is suppressed so ActionCable cannot
  # deliver a stale full replace after partial stream updates.
  def broadcast_refresh!(content: nil, thinking_text: nil)
    locals = message_locals
    locals[:content] = content unless content.nil?
    locals[:thinking_text] = thinking_text unless thinking_text.nil?

    broadcast_replace_to(
      "chat_#{chat_id}",
      target: "message_#{id}",
      partial: to_partial_path,
      locals: locals
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
    return if assistant_message? && ChatResponseControl.responding?(chat_id)

    broadcast_refresh!
  end

  def broadcast_message_removed
    broadcast_remove_to("chat_#{chat_id}")
  end

  def message_locals
    { message: self, assistant: self, user: self, system: self, tool: self }
  end

  def assistant_message?
    role.to_s == "assistant"
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
