# frozen_string_literal: true

require "base64"

class ImageUnderstandingsController < ApplicationController
  def new
    @prompt = params[:prompt].to_s if params[:prompt].present?
  end

  def create
    @prompt = params[:prompt].to_s.strip
    uploaded = params[:image]

    if uploaded.blank?
      return render_create_error("画像を選択してください")
    end

    if @prompt.blank?
      return render_create_error("プロンプトを入力してください")
    end

    ChatImageAttachments.validate_uploads!([ uploaded ])
    image_data = uploaded.read
    mime_type = uploaded.content_type.presence || "image/png"
    @image_data_url = build_data_url(image_data, mime_type)
    chat = build_graph_chat!(uploaded: uploaded, image_data: image_data)
    @agent_run = AgentGraph::ImageUnderstandingGraphRunner.call(chat, question: @prompt)
    return render_create_error(@agent_run.error_message.presence || "画像解析に失敗しました") if @agent_run.failed?

    @result = @agent_run.state["final_answer"].presence || @agent_run.state["analysis"]

    respond_to do |format|
      format.html { render :new }
      format.json do
        render json: {
          result: @result,
          prompt: @prompt,
          image_data_url: @image_data_url,
          agent_run_id: @agent_run.id,
          agent_run_path: chat_agent_run_path(@agent_run.chat, @agent_run)
        }
      end
    end
  rescue ArgumentError, VisionChatService::Error, LlamaCppClient::Error => e
    render_create_error(e.message)
  end

  private

  def build_graph_chat!(uploaded:, image_data:)
    model = ChatModelCatalog.default_model || Model.order(:id).first
    raise ArgumentError, "利用可能なチャットモデルがありません" unless model

    chat = Chat.create!(model: model)
    Message.suppressing_turbo_broadcasts do
      message = chat.messages.create!(role: :user, content: @prompt)
      message.attachments.attach(
        io: StringIO.new(image_data),
        filename: uploaded.original_filename.presence || "image",
        content_type: uploaded.content_type.presence || "image/png"
      )
    end
    chat
  end

  def build_data_url(image_data, mime_type)
    "data:#{mime_type};base64,#{Base64.strict_encode64(image_data)}"
  end

  def render_create_error(message)
    respond_to do |format|
      format.html do
        flash.now[:alert] = message
        render :new, status: :unprocessable_entity
      end
      format.json { render json: { error: message }, status: :unprocessable_entity }
    end
  end
end
