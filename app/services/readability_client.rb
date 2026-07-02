# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class ReadabilityClient
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
    base_url: NyoyConnectionStore.url(:readability),
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT
  )
    @base_url = base_url.to_s.strip.sub(%r{/\z}, "")
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def configured?
    @base_url.present? && NyoyConnectionStore.enabled?(:readability)
  end

  def extract(url, content_format: "markdown")
    raise Error, "readability-js-server が未設定です" unless configured?

    post_json("/", url: url.to_s, contentFormat: content_format)
  end

  private

  def post_json(path, payload)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Accept"] = "application/json"
    req.body = JSON.generate(payload)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.use_ssl = uri.scheme == "https"

    response = http.request(req)
    body = response.body.to_s
    data = body.present? ? JSON.parse(body) : {}

    return data if response.is_a?(Net::HTTPSuccess)

    details = data["details"]
    message = if details.is_a?(Hash)
                details["message"].presence || data["error"].presence || body
              else
                data["error"].presence || body.presence || "HTTP #{response.code}"
              end
    code = details.is_a?(Hash) ? details["code"] : nil
    raise Error.new(message, status: response.code.to_i, code: code)
  rescue JSON::ParserError
    raise Error, "readability-js-server の応答が JSON ではありません（HTTP #{response.code}）"
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "readability-js-server に接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "readability-js-server がタイムアウトしました"
  end
end
