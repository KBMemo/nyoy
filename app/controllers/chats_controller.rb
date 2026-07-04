class ChatsController < ApplicationController
  before_action :set_chat, only: %i[show destroy]
  before_action :load_chat_models, only: %i[new create]

  def index
    @chats = Chat.includes(:model).order(created_at: :desc)
  end

  def new
    @chat = Chat.new
    @selected_model = params[:model]
  end

  def create
    prompt = params.dig(:chat, :prompt).to_s.strip
    uploads = Array(params.dig(:chat, :attachments)).compact

    if prompt.blank? && uploads.empty?
      @chat = Chat.new
      @selected_model = params.dig(:chat, :model)
      flash.now[:alert] = "最初のメッセージまたは画像を入力してください"
      return render :new, status: :unprocessable_entity
    end

    begin
      ChatImageAttachments.validate_uploads!(uploads)
    rescue ArgumentError => e
      @chat = Chat.new
      @selected_model = params.dig(:chat, :model)
      flash.now[:alert] = e.message
      return render :new, status: :unprocessable_entity
    end

    model = selected_chat_model(params.dig(:chat, :model))
    @chat = Chat.create!(model: model)
    message = @chat.messages.create!(
      role: :user,
      content: prompt.presence || ChatImageAttachments::PLACEHOLDER
    )
    message.attachments.attach(uploads) if uploads.any?
    TsuzuraMediaUploader.archive_attachments!(message.attachments) if message.attachments.attached?
    ChatResponseJob.perform_later(@chat.id)

    redirect_to @chat, notice: "チャットを開始しました"
  end

  def show
    @message = @chat.messages.build
  end

  def destroy
    @chat.destroy!
    redirect_to chats_path, notice: "チャットを削除しました", status: :see_other
  end

  private

  def set_chat
    @chat = Chat.find(params[:id])
  end

  def load_chat_models
    @chat_models = available_chat_models
  end

  def selected_chat_model(model_id)
    return Model.find(model_id) if model_id.present?

    ChatModelCatalog.default_model || available_chat_models.first || begin
      ChatModelCatalog.seed!
      Model.find_by!(provider: "openai", model_id: ChatModelCatalog.model_ids.first)
    end
  end

  def default_chat_model_id
    ChatModelCatalog.default_model&.id || @chat_models.first&.id
  end
  helper_method :default_chat_model_id
end
