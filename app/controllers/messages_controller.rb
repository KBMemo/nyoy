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

    Message.suppressing_turbo_broadcasts do
      @message = @chat.messages.create!(
        role: :user,
        content: content.presence || ChatImageAttachments::PLACEHOLDER
      )
      @message.attachments.attach(uploads) if uploads.any?
      TsuzuraMediaUploader.archive_attachments!(@message.attachments) if @message.attachments.attached?
    end

    ChatResponseControl.mark_running!(@chat)
    ChatResponseJob.perform_later(@chat.id)
    load_agent_run_history

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat }
    end
  end

  private

  def set_chat
    @chat = Chat.find(params[:chat_id])
  end

  def load_agent_run_history
    @recent_agent_runs = @chat.agent_runs.recent.limit(5)
    @show_agent_run_history = @recent_agent_runs.any? || user_image_attachment_messages?
  end

  def user_image_attachment_messages?
    @chat.messages.where(role: :user).joins(:attachments_attachments).exists?
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
