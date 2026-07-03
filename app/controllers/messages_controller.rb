class MessagesController < ApplicationController
  before_action :set_chat

  def create
    content = params.dig(:message, :content).to_s.strip
    uploads = Array(params.dig(:message, :attachments)).compact

    if content.blank? && uploads.empty?
      return render_form_error("メッセージまたは画像を入力してください")
    end

    begin
      ChatImageAttachments.validate_uploads!(uploads)
    rescue ArgumentError => e
      return render_form_error(e.message)
    end

    @message = @chat.messages.create!(
      role: :user,
      content: content.presence || ChatImageAttachments::PLACEHOLDER
    )
    @message.attachments.attach(uploads) if uploads.any?
    TsuzuraMediaUploader.archive_attachments!(@message.attachments) if @message.attachments.attached?

    ChatResponseJob.perform_later(@chat.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat }
    end
  end

  private

  def set_chat
    @chat = Chat.find(params[:chat_id])
  end

  def render_form_error(message)
    @message = @chat.messages.build(content: params.dig(:message, :content))
    @message.errors.add(:base, message)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "new_message",
          partial: "messages/form",
          locals: { chat: @chat, message: @message }
        ), status: :unprocessable_entity
      end
      format.html do
        flash.now[:alert] = message
        render "chats/show", status: :unprocessable_entity
      end
    end
  end
end
