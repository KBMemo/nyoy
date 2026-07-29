# frozen_string_literal: true

class Api::AudioController < ActionController::API
  ALLOWED_AUDIO_TYPES = %w[audio/webm audio/ogg audio/wav audio/x-wav audio/mp4].freeze
  MAX_UPLOAD_BYTES = 10.megabytes

  before_action :authenticate!

  def health
    render json: LfmAudioClient.new.health
  rescue LfmAudioClient::Error => error
    render_error(error, status: :service_unavailable)
  end

  def transcribe
    file = params.require(:file)
    validate_audio_file!(file)

    text = LfmAudioClient.new.transcribe(
      io: file.tempfile,
      filename: file.original_filename.presence || "recording.webm",
      content_type: file.content_type,
      language: params.fetch(:language, "ja"),
      prompt: params[:prompt]
    )
    render json: { text: text }
  rescue ActionController::ParameterMissing => error
    render_error(error, status: :unprocessable_entity)
  rescue LfmAudioClient::Error => error
    render_audio_error(error)
  end

  def speech
    text = params.require(:input).to_s
    audio = LfmAudioClient.new.synthesize(text: text)
    send_data audio.data, type: audio.content_type, disposition: "inline", filename: audio.filename
  rescue ActionController::ParameterMissing => error
    render_error(error, status: :unprocessable_entity)
  rescue LfmAudioClient::Error => error
    render_audio_error(error)
  end

  private

  def authenticate!
    expected = Mcp.api_token.to_s
    actual = bearer_token
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(actual, expected)

    response.headers["WWW-Authenticate"] = 'Bearer realm="nyoy-audio", charset="UTF-8"'
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def bearer_token
    header = request.authorization.to_s
    return "" unless header.match?(/\ABearer /i)

    header.split(" ", 2).last.to_s.strip
  end

  def validate_audio_file!(file)
    unless file.content_type.in?(ALLOWED_AUDIO_TYPES)
      raise LfmAudioClient::Error.new("対応していない音声ファイル形式です", status: 422)
    end
    return if file.size <= MAX_UPLOAD_BYTES

    raise LfmAudioClient::Error.new("音声ファイルが大きすぎます", status: 413)
  end

  def render_audio_error(error)
    status = error.status.to_i.between?(400, 499) ? error.status : :service_unavailable
    render_error(error, status: status)
  end

  def render_error(error, status:)
    render json: { error: error.message }, status: status
  end
end
