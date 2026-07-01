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

    image_data = uploaded.read
    mime_type = uploaded.content_type.presence || "image/png"
    @image_data_url = build_data_url(image_data, mime_type)
    @result = VisionChatService.new.analyze(
      image: image_data,
      mime_type: mime_type,
      prompt: @prompt
    )

    respond_to do |format|
      format.html { render :new }
      format.json { render json: { result: @result, prompt: @prompt, image_data_url: @image_data_url } }
    end
  rescue VisionChatService::Error, LlamaCppClient::Error => e
    render_create_error(e.message)
  end

  private

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
