# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class TsurezureClient
  class Error < StandardError
    attr_reader :status, :code

    def initialize(message, status: nil, code: nil)
      super(message)
      @status = status
      @code = code
    end
  end

  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 30

  def initialize(
    base_url: NyoyConnectionStore.url(:kbmemo),
    api_token: NyoyConnectionStore.api_token(:kbmemo),
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

  def list_memos(q: nil, tag: nil, updated_since: nil, include_drafts: false, fields: nil, limit: 50, offset: 0)
    query = compact_query(
      q: q,
      tag: tag,
      updated_since: iso8601(updated_since),
      include_drafts: include_drafts ? true : nil,
      fields: fields,
      limit: limit,
      offset: offset
    )
    get_json("/memos#{query}")
  end

  def get_memo(memo_ref, fields: nil)
    query = compact_query(fields: fields)
    get_json("/memos/#{encode_ref(memo_ref)}#{query}")
  end

  def create_memo(title: nil, body:, tags: nil, visibility: nil, properties: nil, commit: true)
    payload = compact_body(
      title: title,
      body: body,
      tags: tags,
      visibility: visibility,
      properties: properties,
      commit: commit
    )
    post_json("/memos", payload)
  end

  def update_memo(memo_ref, updated_at:, title: nil, body: nil, append_body: nil, tags: nil, visibility: nil, properties: nil, commit: nil)
    payload = compact_body(
      updated_at: iso8601(updated_at),
      title: title,
      body: body,
      append_body: append_body,
      tags: tags,
      visibility: visibility,
      properties: properties,
      commit: commit
    )
    patch_json("/memos/#{encode_ref(memo_ref)}", payload)
  end

  def export_memos(updated_since: nil, include_drafts: false, fields: nil, cursor: nil, limit: 100)
    query = compact_query(
      updated_since: iso8601(updated_since),
      include_drafts: include_drafts ? true : nil,
      fields: fields,
      cursor: cursor,
      limit: limit
    )
    get_json("/memos/export#{query}")
  end

  private

  def normalize_api_root(base_url)
    root = base_url.to_s.strip.sub(%r{/\z}, "")
    return "" if root.blank?

    root.end_with?("/api/v1") ? root : "#{root}/api/v1"
  end

  def encode_ref(memo_ref)
    URI.encode_uri_component(memo_ref.to_s)
  end

  def iso8601(value)
    return value.iso8601 if value.respond_to?(:iso8601)

    value.presence
  end

  def compact_query(**params)
    pairs = params.filter_map do |key, value|
      next if value.nil?
      next if value == ""

      "#{key}=#{URI.encode_uri_component(value.to_s)}"
    end
    pairs.empty? ? "" : "?#{pairs.join('&')}"
  end

  def compact_body(**params)
    params.each_with_object({}) do |(key, value), body|
      next if value.nil?
      next if value == "" && key != :body

      body[key] = value
    end
  end

  def get_json(path)
    request_json(:get, path)
  end

  def post_json(path, payload)
    request_json(:post, path, payload)
  end

  def patch_json(path, payload)
    request_json(:patch, path, payload)
  end

  def request_json(method, path, payload = nil)
    raise Error, "徒然 API が未設定です（kbmemo の URL と API トークンを設定してください）" unless configured?

    uri = URI("#{@api_root}#{path}")
    req = build_request(method, uri, payload)

    response = perform_request(uri, req)
    parse_response(response)
  end

  def build_request(method, uri, payload)
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
    raise Error, "徒然 API に接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "徒然 API がタイムアウトしました"
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
    raise Error, "徒然 API の応答が JSON ではありません（HTTP #{response.code}）"
  end
end
