# frozen_string_literal: true

class GenerationMemoSavesController < ApplicationController
  ALLOWED_RECORD_TYPES = %w[ImageGeneration MemoIllustration Img2imgGeneration].freeze

  def create
    unless GeneratedImageMemoSaver.available?
      return respond_failure("徒然・葛籠の接続が未設定です")
    end

    attachment = ActiveStorage::Attachment.find_by(id: params[:attachment_id])
    unless attachment && ALLOWED_RECORD_TYPES.include?(attachment.record_type)
      return respond_failure("保存できない画像です")
    end

    result = GeneratedImageMemoSaver.call(attachment: attachment)
    notice = result["media_append_error"].present? ? "徒然に保存しました（画像マクロの追記に失敗しました）" : "徒然に保存しました"
    respond_success(result:, attachment:, notice:)
  rescue GeneratedImageMemoSaver::Error, TsurezureClient::Error, TsuzuraClient::Error => e
    respond_failure(e.message)
  end

  private

  def respond_success(result:, attachment:, notice:)
    memo_url = TsurezureMemoUrl.absolute(result)

    respond_to do |format|
      format.json do
        render json: {
          ok: true,
          notice: notice,
          url: memo_url,
          memo_id: result["id"],
          memo_uid: result["uid"]
        }
      end
      format.html do
        if memo_url.present?
          redirect_to memo_url, notice: notice, allow_other_host: true
        else
          redirect_back fallback_location: polymorphic_path(attachment.record), notice: notice
        end
      end
    end
  end

  def respond_failure(message)
    respond_to do |format|
      format.json { render json: { ok: false, error: message }, status: :unprocessable_entity }
      format.html { redirect_back fallback_location: root_path, alert: message }
    end
  end
end
