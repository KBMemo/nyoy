class ChatsController < ApplicationController
  before_action :set_chat, only: %i[show destroy cancel update_web_tool_limits]
  before_action :load_chat_models, only: %i[new create]
  before_action :load_web_tool_settings, only: %i[show update_web_tool_limits]

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
    ChatResponseControl.mark_running!(@chat)
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

  def cancel
    if @chat.responding?
      ChatResponseControl.cancel!(@chat)
      redirect_to @chat, notice: "応答の中止を要求しました。"
    else
      redirect_to @chat, alert: "実行中の応答はありません。"
    end
  end

  def update_web_tool_limits
    connection = @searxng_connection
    unless connection
      redirect_to @chat, alert: "SearXNG 接続が未設定です。"
      return
    end

    settings = connection.searxng_settings.to_h.merge(
      "max_searches_per_turn" => params[:max_searches_per_turn],
      "max_fetches_per_turn" => params[:max_fetches_per_turn]
    )
    connection.assign_searxng_settings(settings)

    if connection.save
      redirect_to @chat, notice: "Web ツール上限を更新しました。"
    else
      redirect_to @chat, alert: connection.errors.full_messages.to_sentence
    end
  end

  private

  def set_chat
    @chat = Chat.find(params[:id])
  end

  def load_web_tool_settings
    @searxng_connection = ServiceConnection.find_by(key: "searxng")
    @web_tool_settings = @searxng_connection&.searxng_settings || SearxngSettings.load
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
