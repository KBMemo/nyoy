# frozen_string_literal: true

require "json"
require "multipart/post"
require "net/http"
require "net/http/post/multipart"
require "uri"

class TsuzuraClient
  class Error < StandardError
    attr_reader :status, :code

    def initialize(message, status: nil, code: nil)
      super(message)
      @status = status
      @code = code
    end
  end

  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 120

  def initialize(
    base_url: NyoyConnectionStore.url(:tsuzura),
    api_token: NyoyConnectionStore.api_token(:tsuzura),
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT
  )
    @api_root = normalize_api_root(base_url)
    @api_token = api_token.to_s.strip
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def configured?
    @api_root.present? && @api_token.present?
  end

  def list_albums
    get_json("/albums")
  end

  def get_media(media_id)
    get_json("/media/#{encode_ref(media_id)}")
  end

  def lookup_media(checksum:)
    get_json("/media/lookup#{compact_query(checksum: checksum)}")
  end

  def upload_batch(files:, album_title: nil, album_id: nil, album_ids: nil, auto_date_albums: nil)
    raise Error, "files required" if Array(files).empty?

    fields = {}
    fields[:album_title] = album_title if album_title.present?
    fields[:album_id] = album_id if album_id.present?
    Array(album_ids).each { |id| (fields[:"album_ids[]"] ||= []) << id }
    fields[:auto_date_albums] = true if auto_date_albums

    upload_ios = Array(files).map { |file| build_upload_io(file) }
    fields[:files] = upload_ios.one? ? upload_ios.first : upload_ios

    post_multipart("/media/batch", fields)
  end

  private

  def normalize_api_root(base_url)
    root = base_url.to_s.strip.sub(%r{/\z}, "")
    return "" if root.blank?

    root.end_with?("/v1") ? root : "#{root}/v1"
  end

  def encode_ref(value)
    URI.encode_uri_component(value.to_s)
  end

  def compact_query(**params)
    pairs = params.filter_map do |key, value|
      next if value.nil?
      next if value == ""

      "#{key}=#{URI.encode_uri_component(value.to_s)}"
    end
    pairs.empty? ? "" : "?#{pairs.join('&')}"
  end

  def build_upload_io(file)
    case file
    when Hash
      io = file[:io] || file["io"]
      filename = file[:filename] || file["filename"] || "upload.bin"
      content_type = file[:content_type] || file["content_type"] || "application/octet-stream"
      Multipart::Post::UploadIO.new(io, content_type, filename)
    else
      file
    end
  end

  def get_json(path)
    request_json(:get, path)
  end

  def post_multipart(path, fields)
    raise Error, "葛籠 API が未設定です（tsuzura の URL と API トークンを設定してください）" unless configured?

    uri = URI("#{@api_root}#{path}")
    req = Net::HTTP::Post::Multipart.new(uri.path, fields)
    req["Authorization"] = "Bearer #{@api_token}"
    req["Accept"] = "application/json"

    response = perform_request(uri, req)
    parse_response(response)
  end

  def request_json(method, path, payload = nil)
    raise Error, "葛籠 API が未設定です（tsuzura の URL と API トークンを設定してください）" unless configured?

    uri = URI("#{@api_root}#{path}")
    req = build_json_request(method, uri, payload)

    response = perform_request(uri, req)
    parse_response(response)
  end

  def build_json_request(method, uri, payload)
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
    req = klass.new(uri)
    req["Authorization"] = "Bearer #{@api_token}"
    req["Accept"] = "application/json"
    if payload
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(payload)
    end
    req
  end

  def perform_request(uri, req)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.use_ssl = uri.scheme == "https"
    http.request(req)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "葛籠 API に接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "葛籠 API がタイムアウトしました"
  end

  def parse_response(response)
    body = response.body.to_s
    payload = body.present? ? JSON.parse(body) : {}

    return payload if response.is_a?(Net::HTTPSuccess)

    error = payload["error"]
    message = if error.is_a?(Hash)
                error["message"].presence || error["code"].presence || body
              else
                error.presence || body.presence || "HTTP #{response.code}"
              end
    raise Error.new(message, status: response.code.to_i, code: error.is_a?(Hash) ? error["code"] : nil)
  rescue JSON::ParserError
    raise Error, "葛籠 API の応答が JSON ではありません（HTTP #{response.code}）"
  end
end
