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
      flash.now[:alert] = "画像を選択してください"
      return render :new, status: :unprocessable_entity
    end

    if @prompt.blank?
      flash.now[:alert] = "プロンプトを入力してください"
      return render :new, status: :unprocessable_entity
    end

    image_data = uploaded.read
    mime_type = uploaded.content_type.presence || "image/png"
    @image_data_url = "data:#{mime_type};base64,#{Base64.strict_encode64(image_data)}"
    @result = VisionChatService.new.analyze(
      image: image_data,
      mime_type: mime_type,
      prompt: @prompt
    )
    render :new
  rescue VisionChatService::Error, LlamaCppClient::Error => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end
end
