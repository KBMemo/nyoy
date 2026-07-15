# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# searfront gateway client (`GET /v1/search`).
# Normalizes responses to the same shape ChatTools::WebSearch expects from SearXNG.
class SearfrontClient
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 45
  DEFAULT_WAIT_SECONDS = 15
  DEFAULT_POLL_INTERVAL = 2.0
  MAX_POLL_SECONDS = 45

  @search_mutex = Mutex.new
  @active_searches = 0
  @search_condition = ConditionVariable.new

  class << self
    attr_reader :search_mutex, :search_condition

    def active_searches
      @active_searches
    end

    def active_searches=(value)
      @active_searches = value
    end
  end

  def initialize(
    base_url: NyoyConnectionStore.url(:searxng),
    api_token: NyoyConnectionStore.api_token(:searxng),
    settings: nil,
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT,
    wait_seconds: DEFAULT_WAIT_SECONDS
  )
    @base_url = base_url.to_s.strip.sub(%r{/\z}, "")
    @api_token = api_token.to_s.strip
    @settings = settings
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @wait_seconds = wait_seconds.to_i.clamp(0, 30)
  end

  def configured?
    @base_url.present? && @api_token.present?
  end

  def search(q:, limit: nil, categories: nil)
    raise Error, "searfront が未設定です（接続設定の URL と API トークンを設定してください）" unless configured?

    settings = resolved_settings
    limit = settings.result_count if limit.nil?
    capped = clamp_limit(limit, settings)

    with_concurrency_limit(settings.concurrent_searches) do
      with_retry(settings.retry_count) do
        payload = request_search(q: q, limit: capped, categories: categories)
        normalize_payload(payload, q: q, limit: capped)
      end
    end
  end

  private

  def resolved_settings
    @settings || SearxngSettings.load
  end

  def clamp_limit(limit, settings)
    value = limit.to_i
    value = settings.result_count if value <= 0
    value.clamp(1, 10)
  end

  def request_search(q:, limit:, categories:)
    query = compact_query(
      q: q,
      limit: limit,
      categories: categories.presence || "general",
      language: "ja-JP",
      wait_seconds: @wait_seconds
    )
    status, payload = get_json("/v1/search#{query}")
    return wait_for_request(payload) if status == 202

    payload
  end

  def wait_for_request(payload)
    request_id = payload["request_id"].to_s
    raise Error.new("searfront が request_id なしで 202 を返しました", status: 202) if request_id.blank?

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MAX_POLL_SECONDS
    interval = payload["poll_after_seconds"].to_f
    interval = DEFAULT_POLL_INTERVAL if interval <= 0

    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise Error, "searfront の検索完了待ちがタイムアウトしました" if remaining <= 0

      backoff_sleep([ interval, remaining ].min)
      status, body = get_json("/v1/search_requests/#{URI.encode_uri_component(request_id)}")
      return body if status == 200 && body["status"].to_s != "pending"
      next if status == 202 || body["status"].to_s == "pending"

      raise Error.new(extract_error_message(body, fallback: "HTTP #{status}"), status: status)
    end
  end

  def normalize_payload(payload, q:, limit:)
    results = Array(payload["results"]).map { |result| normalize_result(result) }.first(limit)
    sources = Array(payload["sources"])

    {
      "query" => payload["normalized_query"].presence || payload["query"].presence || q,
      "number_of_results" => results.size,
      "results" => results,
      "engines" => sources.join(","),
      "sources" => sources,
      "cache" => payload["cache"],
      "warnings" => Array(payload["warnings"]),
      "request_id" => payload["request_id"],
      "timing_ms" => payload["timing_ms"]
    }.compact
  end

  def normalize_result(result)
    engines = Array(result["engines"]).map(&:to_s).reject(&:blank?)
    {
      "title" => result["title"].to_s,
      "url" => (result["url"].presence || result["canonical_url"]).to_s,
      "content" => (result["snippet"].presence || result["content"]).to_s,
      "engine" => engines.first.presence || result["source"].to_s.presence
    }.compact
  end

  def with_concurrency_limit(limit)
    self.class.search_mutex.synchronize do
      while self.class.active_searches >= limit
        self.class.search_condition.wait(self.class.search_mutex)
      end
      self.class.active_searches += 1
    end

    yield
  ensure
    self.class.search_mutex.synchronize do
      self.class.active_searches -= 1
      self.class.search_condition.signal
    end
  end

  def with_retry(max_retries)
    attempts = 0
    begin
      yield
    rescue Error => e
      attempts += 1
      raise if attempts > max_retries || !retryable_error?(e)

      backoff_sleep(0.4 * attempts)
      retry
    end
  end

  def retryable_error?(error)
    status = error.status
    status.nil? || status >= 500
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
    req["Authorization"] = "Bearer #{@api_token}"

    response = perform_request(uri, req)
    body = response.body.to_s
    payload = body.present? ? JSON.parse(body) : {}
    code = response.code.to_i

    return [ code, payload ] if response.is_a?(Net::HTTPSuccess) || code == 202

    raise Error.new(extract_error_message(payload, fallback: body.presence || "HTTP #{code}"), status: code)
  rescue JSON::ParserError
    raise Error, "searfront の応答が JSON ではありません（HTTP #{response&.code}）"
  end

  def extract_error_message(payload, fallback:)
    error = payload["error"]
    case error
    when Hash
      error["message"].presence || error["code"].presence || fallback
    when String
      error.presence || fallback
    else
      fallback
    end
  end

  def backoff_sleep(seconds)
    sleep(seconds)
  end

  def perform_request(uri, req)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.use_ssl = uri.scheme == "https"
    http.request(req)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "searfront に接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "searfront がタイムアウトしました"
  end
end
