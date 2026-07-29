# frozen_string_literal: true

require "json"
require "multipart/post"
require "net/http"
require "net/http/post/multipart"
require "uri"

class LfmAudioClient
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  Audio = Data.define(:data, :content_type, :filename)

  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 180

  def initialize(
    base_url: NyoyConnectionStore.url(:lfm_audio),
    api_token: NyoyConnectionStore.api_token(:lfm_audio),
    model: NyoyConnectionStore.server_model(:lfm_audio),
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT
  )
    @base_url = base_url.to_s.strip.sub(%r{/\z}, "")
    @api_token = api_token.to_s.strip
    @model = model.to_s.strip
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def configured?
    @base_url.present? && @api_token.present? && @model.present? && NyoyConnectionStore.enabled?(:lfm_audio)
  end

  def health
    raise Error, "LFM Audio API が未設定です" unless configured?

    uri = URI("#{@base_url}/health")
    response = perform_request(uri, Net::HTTP::Get.new(uri))
    parse_json_response(response)
  end

  def transcribe(io:, filename:, content_type:, language: "ja", prompt: nil)
    raise Error, "LFM Audio API が未設定です" unless configured?

    uri = URI("#{@base_url}/v1/audio/transcriptions")
    fields = {
      file: Multipart::Post::UploadIO.new(io, content_type, filename),
      model: @model,
      language: language
    }
    fields[:prompt] = prompt if prompt.present?
    response = perform_request(uri, authenticated_multipart_request(uri, fields))
    parse_json_response(response).fetch("text")
  end

  def synthesize(text:, voice: "default", response_format: "wav")
    raise Error, "LFM Audio API が未設定です" unless configured?

    uri = URI("#{@base_url}/v1/audio/speech")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"
    request["Accept"] = "audio/wav"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      model: @model,
      input: text,
      voice: voice,
      response_format: response_format
    )

    response = perform_request(uri, request)
    parse_audio_response(response)
  end

  private

  def authenticated_multipart_request(uri, fields)
    request = Net::HTTP::Post::Multipart.new(uri.path, fields)
    request["Authorization"] = "Bearer #{@api_token}"
    request["Accept"] = "application/json"
    request
  end

  def perform_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.use_ssl = uri.scheme == "https"
    http.request(request)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => error
    raise Error, "LFM Audio API に接続できませんでした（#{error.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "LFM Audio API がタイムアウトしました"
  end

  def parse_json_response(response)
    body = response.body.to_s
    data = body.present? ? JSON.parse(body) : {}
    return data if response.is_a?(Net::HTTPSuccess)

    raise Error.new(error_message(data, body, response.code), status: response.code.to_i)
  rescue JSON::ParserError
    raise Error, "LFM Audio API の応答が JSON ではありません（HTTP #{response.code}）"
  end

  def parse_audio_response(response)
    if response.is_a?(Net::HTTPSuccess)
      return Audio.new(
        data: response.body.to_s,
        content_type: response["Content-Type"].presence || "audio/wav",
        filename: "speech.wav"
      )
    end

    body = response.body.to_s
    data = body.present? ? JSON.parse(body) : {}
    raise Error.new(error_message(data, body, response.code), status: response.code.to_i)
  rescue JSON::ParserError
    raise Error, "LFM Audio API の応答が JSON ではありません（HTTP #{response.code}）"
  end

  def error_message(data, body, status)
    data["detail"].presence || data["error"].presence || body.presence || "HTTP #{status}"
  end
end
