class ChatsController < ApplicationController
  before_action :set_chat, only: %i[show destroy cancel update_chat_settings]
  before_action :load_chat_models, only: %i[new create]
  before_action :load_new_chat_sampling, only: %i[new create]
  before_action :load_chat_settings, only: %i[show update_chat_settings]

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
    @chat = Chat.create!(model: model, llm_params: initial_llm_params)
    Message.suppressing_turbo_broadcasts do
      message = @chat.messages.create!(
        role: :user,
        content: prompt.presence || ChatImageAttachments::PLACEHOLDER
      )
      message.attachments.attach(uploads) if uploads.any?
      TsuzuraMediaUploader.archive_attachments!(message.attachments) if message.attachments.attached?
    end
    ChatResponseControl.mark_running!(@chat)
    ChatResponseJob.perform_later(@chat.id)

    redirect_to @chat, notice: "チャットを開始しました"
  end

  def show
    @message = @chat.messages.build
    @pending_agent_run = @chat.agent_runs.pending_decision.recent.first
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

  def update_chat_settings
    @chat.update!(llm_params: ChatLlmSettings.normalize(chat_llm_settings_params))

    if @searxng_connection&.enabled?
      settings = @searxng_connection.searxng_settings.to_h.merge(web_tool_settings_params)
      @searxng_connection.assign_searxng_settings(settings)

      unless @searxng_connection.save
        redirect_to @chat, alert: @searxng_connection.errors.full_messages.to_sentence
        return
      end
    end

    redirect_to @chat, notice: "チャット設定を更新しました。"
  end

  private

  def set_chat
    @chat = Chat.find(params[:id])
  end

  def load_new_chat_sampling
    @llm_sampling_presets = LlmSamplingPreset.enabled.ordered
    model = selected_chat_model(params.dig(:chat, :model).presence || params[:model])
    defaults = ChatLlmSettings.defaults_for(model: model)
    submitted = params.dig(:chat)&.permit(*LlmSamplingParams::KEYS)
    @chat_llm_settings =
      if submitted.present?
        ChatLlmSettings.from(ChatLlmSettings.merge_layers(defaults.to_h, submitted))
      else
        defaults
      end
  end

  def initial_llm_params
    model = selected_chat_model(params.dig(:chat, :model))
    defaults = ChatLlmSettings.defaults_for(model: model).to_h
    submitted = ChatLlmSettings.normalize(params.fetch(:chat, {}).permit(*LlmSamplingParams::KEYS))
    ChatLlmSettings.merge_layers(defaults, submitted)
  end

  def load_chat_settings
    @searxng_connection = ServiceConnection.find_by(key: "searxng")
    @web_tool_settings = @searxng_connection&.searxng_settings || SearxngSettings.load
    @chat_llm_settings = ChatLlmSettings.effective_for(@chat)
    @llm_sampling_presets = LlmSamplingPreset.enabled.ordered
  end

  def chat_llm_settings_params
    params.permit(*LlmSamplingParams::KEYS)
  end

  def web_tool_settings_params
    params.permit(:max_searches_per_turn, :max_fetches_per_turn).to_h
  end

  def load_chat_models
    @chat_model_groups = ChatModelCatalog.grouped_model_options
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
