# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class SearxngClient
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 15

  def initialize(
    base_url: NyoyConnectionStore.url(:searxng),
    api_token: NyoyConnectionStore.api_token(:searxng),
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT
  )
    @base_url = base_url.to_s.strip.sub(%r{/\z}, "")
    @api_token = api_token.to_s.strip
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def configured?
    @base_url.present?
  end

  def search(q:, limit: 10, categories: nil)
    raise Error, "SearXNG が未設定です（searxng の URL を設定してください）" unless configured?

    query = compact_query(q: q, format: "json", categories: categories)
    payload = get_json("/search#{query}")
    results = Array(payload["results"]).first(clamp_limit(limit)).map { |result| normalize_result(result) }

    {
      "query" => payload["query"].presence || q,
      "number_of_results" => results.size,
      "results" => results
    }
  end

  private

  def clamp_limit(limit)
    value = limit.to_i
    value = 10 if value <= 0
    [value, 20].min
  end

  def normalize_result(result)
    {
      "title" => result["title"].to_s,
      "url" => result["url"].to_s,
      "content" => result["content"].to_s,
      "engine" => result["engine"].to_s.presence
    }.compact
  end

  def compact_query(**params)
    pairs = params.filter_map do |key, value|
      next if value.nil?
      next if value == ""

      "#{key}=#{URI.encode_uri_component(value.to_s)}"
    end
    pairs.empty? ? "" : "?#{pairs.join('&')}"
  end

  def get_json(path)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Get.new(uri)
    req["Accept"] = "application/json"
    req["User-Agent"] = "Nyoy/1.0"
    req["Authorization"] = "Bearer #{@api_token}" if @api_token.present?

    response = perform_request(uri, req)
    body = response.body.to_s
    payload = body.present? ? JSON.parse(body) : {}

    return payload if response.is_a?(Net::HTTPSuccess)

    message = payload["error"].presence || body.presence || "HTTP #{response.code}"
    raise Error.new(message, status: response.code.to_i)
  rescue JSON::ParserError
    raise Error, "SearXNG の応答が JSON ではありません（HTTP #{response.code}）"
  end

  def perform_request(uri, req)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.use_ssl = uri.scheme == "https"
    http.request(req)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "SearXNG に接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "SearXNG がタイムアウトしました"
  end
end
