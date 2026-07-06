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

  def tool_call_message?
    return false unless respond_to?(:tool_calls_association)

    tool_calls_association.exists?
  end

  def broadcast_rendered_content!(text = nil, seq: nil)
    ChatUiBroadcaster.assistant_content(self, text || content, seq: seq)
  end

  def broadcast_rendered_thinking!(text, seq: nil)
    ChatUiBroadcaster.assistant_thinking(self, text, seq: seq)
  end

  # Explicit full-bubble refresh used when a streaming turn finishes. While the
  # chat is responding?, after_update_commit is suppressed so ActionCable cannot
  # deliver a stale full replace after partial stream updates.
  def broadcast_refresh!(content: nil, thinking_text: nil, seq: nil)
    ChatUiBroadcaster.assistant_finalized(
      self,
      content: content || self.content,
      thinking_text: thinking_text || self.thinking_text,
      seq: seq
    )
  end

  private

  def broadcast_message_created
    return if broadcasts_suppressed?
    return if stream_managed_assistant?

    ChatUiBroadcaster.message_upsert(self)
  end

  def broadcast_message_updated
    return if broadcasts_suppressed?
    return if stream_managed_assistant? && ChatResponseControl.responding?(chat_id)

    ChatUiBroadcaster.message_upsert(self)
  end

  def broadcast_message_removed
    return if broadcasts_suppressed?

    ChatUiBroadcaster.message_removed(self)
  end

  def message_locals
    { message: self, assistant: self, user: self, system: self, tool: self }
  end

  def assistant_message?
    role.to_s == "assistant"
  end

  def stream_managed_assistant?
    assistant_message? && !tool_call_message? && !chat_error? && !chat_cancelled?
  end

  def broadcasts_suppressed?
    self.class.respond_to?(:suppressed_turbo_broadcasts?) && self.class.suppressed_turbo_broadcasts?
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
