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
    if prompt.blank?
      @chat = Chat.new
      @selected_model = params.dig(:chat, :model)
      flash.now[:alert] = "最初のメッセージを入力してください"
      return render :new, status: :unprocessable_entity
    end

    model = selected_chat_model(params.dig(:chat, :model))
    @chat = Chat.create!(model: model)
    ChatResponseJob.perform_later(@chat.id, prompt)

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

    available_chat_models.first || begin
      ChatModelCatalog.seed!
      Model.find_by!(provider: "openai", model_id: ChatModelCatalog.model_ids.first)
    end
  end
end
