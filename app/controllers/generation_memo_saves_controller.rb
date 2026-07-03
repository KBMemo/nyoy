# frozen_string_literal: true

class GenerationMemoSavesController < ApplicationController
  ALLOWED_RECORD_TYPES = %w[ImageGeneration MemoIllustration Img2imgGeneration].freeze

  def create
    unless GeneratedImageMemoSaver.available?
      redirect_back fallback_location: root_path, alert: "徒然・葛籠の接続が未設定です"
      return
    end

    attachment = ActiveStorage::Attachment.find_by(id: params[:attachment_id])
    unless attachment && ALLOWED_RECORD_TYPES.include?(attachment.record_type)
      redirect_back fallback_location: root_path, alert: "保存できない画像です"
      return
    end

    result = GeneratedImageMemoSaver.call(attachment: attachment)
    memo_url = result["url"]
    notice = result["media_append_error"].present? ? "徒然に保存しました（画像マクロの追記に失敗しました）" : "徒然に保存しました"

    if memo_url.present?
      redirect_to memo_url, notice: notice, allow_other_host: true
    else
      redirect_back fallback_location: polymorphic_path(attachment.record), notice: notice
    end
  rescue GeneratedImageMemoSaver::Error, TsurezureClient::Error, TsuzuraClient::Error => e
    redirect_back fallback_location: root_path, alert: e.message
  end
end
