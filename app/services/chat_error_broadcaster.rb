# frozen_string_literal: true

class ChatErrorBroadcaster
  ERROR_PREFIX = "[[nyoy-error]]"

  def self.fail!(chat, error)
    new(chat, error).call
  end

  def initialize(chat, error)
    @chat = chat
    @error = error
  end

  def call
    @chat.reload
    remove_blank_assistant!
    message = create_error_message!
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

  def create_error_message!
    @chat.messages.create!(role: :assistant, content: "#{ERROR_PREFIX}#{friendly_message}")
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

  def friendly_message
    message = @error.message.to_s

    if context_length_error?
      <<~TEXT.strip
        会話が長すぎます（コンテキスト上限を超えました）。新しいチャットを始めるか、過去のメッセージを減らしてください。

        #{message}
      TEXT
    else
      <<~TEXT.strip
        応答の取得に失敗しました。

        #{message}
      TEXT
    end
  end

  def context_length_error?
    return true if @error.is_a?(RubyLLM::ContextLengthExceededError)

    @error.message.to_s.match?(/context size|context length|context window|too many tokens|token count exceeds/i)
  end
end
