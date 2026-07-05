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
    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{@chat.id}",
      target: "new_message",
      html: MessagesController.render(
        partial: "messages/form",
        locals: {
          chat: @chat,
          message: Message.new,
          form_url: Rails.application.routes.url_helpers.chat_messages_path(@chat)
        }
      )
    )
  end
end
