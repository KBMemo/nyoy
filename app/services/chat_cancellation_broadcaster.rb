# frozen_string_literal: true

class ChatCancellationBroadcaster
  CANCELLED_PREFIX = "[[nyoy-cancelled]]"

  def self.call(chat)
    new(chat).call
  end

  def initialize(chat)
    @chat = chat
  end

  def call
    @chat.reload
    remove_blank_assistant!
    message = create_cancelled_message!
    reset_form!
    message
  end

  private

  def remove_blank_assistant!
    assistant = @chat.messages.where(role: :assistant).order(:id).last
    return if assistant.nil?
    return unless assistant.content.blank?

    assistant.destroy!
  end

  def create_cancelled_message!
    @chat.messages.create!(role: :assistant, content: "#{CANCELLED_PREFIX}応答を中止しました。")
  end

  def reset_form!
    ChatUiBroadcaster.form_updated(@chat)
  end
end
