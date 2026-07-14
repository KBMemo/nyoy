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
  # Used when the configured engines return nothing (CAPTCHA / silent Google block).
  EMPTY_RESULT_FALLBACK_ENGINES = %w[google wikipedia].freeze

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
    read_timeout: DEFAULT_READ_TIMEOUT
  )
    @base_url = base_url.to_s.strip.sub(%r{/\z}, "")
    @api_token = api_token.to_s.strip
    @settings = settings
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def configured?
    @base_url.present?
  end

  def search(q:, limit: nil, categories: nil)
    raise Error, "SearXNG が未設定です（searxng の URL を設定してください）" unless configured?

    settings = resolved_settings
    limit = settings.result_count if limit.nil?
    capped = clamp_limit(limit, settings)

    with_concurrency_limit(settings.concurrent_searches) do
      primary = perform_search(
        q: q,
        limit: capped,
        categories: categories,
        engines: settings.engines_param,
        retry_count: settings.retry_count
      )
      recover_empty_results(primary, q: q, limit: capped, categories: categories, settings: settings)
    end
  end

  private

  def resolved_settings
    @settings || SearxngSettings.load
  end

  def perform_search(q:, limit:, categories:, engines:, retry_count:)
    with_retry(retry_count) do
      query = compact_query(
        q: q,
        format: "json",
        categories: categories,
        engines: engines
      )
      payload = get_json("/search#{query}")
      results = collect_results(payload).first(limit)

      {
        "query" => payload["query"].presence || q,
        "number_of_results" => results.size,
        "results" => results,
        "engines" => engines.to_s,
        "unresponsive_engines" => Array(payload["unresponsive_engines"])
      }.compact
    end
  end

  # DDG often returns CAPTCHA (empty + unresponsive). Google may also return empty
  # without listing itself as unresponsive. Retry without dead engines, then fallback.
  def recover_empty_results(result, q:, limit:, categories:, settings:)
    return result if Array(result["results"]).any?

    attempted = [ settings.engines_param ]
    accumulated_unresponsive = Array(result["unresponsive_engines"])

    remaining = engines_excluding_unresponsive(settings.engine_list, accumulated_unresponsive)
    if remaining.any? && remaining.join(",") != settings.engines_param
      attempted << remaining.join(",")
      retry_result = perform_search(
        q: q,
        limit: limit,
        categories: categories,
        engines: remaining.join(","),
        retry_count: 0
      )
      accumulated_unresponsive |= Array(retry_result["unresponsive_engines"])
      return annotate_recovery(retry_result, attempted, accumulated_unresponsive) if Array(retry_result["results"]).any?
    end

    fallback = EMPTY_RESULT_FALLBACK_ENGINES.join(",")
    return annotate_recovery(result, attempted, accumulated_unresponsive) if attempted.include?(fallback)

    attempted << fallback
    fallback_result = perform_search(
      q: q,
      limit: limit,
      categories: categories,
      engines: fallback,
      retry_count: 0
    )
    accumulated_unresponsive |= Array(fallback_result["unresponsive_engines"])
    annotate_recovery(fallback_result, attempted, accumulated_unresponsive)
  end

  def engines_excluding_unresponsive(engines, unresponsive)
    dead = Array(unresponsive).filter_map { |entry| entry.is_a?(Array) ? entry.first.to_s : entry.to_s }
    engines.reject { |name| dead.include?(name) }
  end

  def annotate_recovery(result, attempted, unresponsive)
    result.merge(
      "engines" => result["engines"],
      "unresponsive_engines" => unresponsive,
      "engines_tried" => attempted
    ).compact
  end

  def clamp_limit(limit, settings)
    value = limit.to_i
    value = settings.result_count if value <= 0
    value.clamp(1, 10)
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

  # Only retry transient failures (network/timeout = no status, or 5xx).
  # 4xx incl. 429 (rate limit / CAPTCHA) are not retried — retrying immediately
  # tends to worsen rate limiting rather than recover.
  def retryable_error?(error)
    status = error.status
    status.nil? || status >= 500
  end

  def collect_results(payload)
    results = Array(payload["results"]).map { |result| normalize_result(result) }
    seen_urls = results.filter_map { |result| result["url"].presence }.to_set

    Array(payload["infoboxes"]).each do |infobox|
      item = normalize_infobox(infobox)
      next if item["url"].blank? || seen_urls.include?(item["url"])

      results << item
      seen_urls << item["url"]
    end

    results
  end

  def normalize_result(result)
    {
      "title" => result["title"].to_s,
      "url" => result["url"].to_s,
      "content" => result["content"].to_s,
      "engine" => result["engine"].to_s.presence
    }.compact
  end

  def normalize_infobox(infobox)
    url = infobox["id"].presence ||
          Array(infobox["urls"]).filter_map { |entry| entry.is_a?(Hash) ? entry["url"].presence : nil }.first

    {
      "title" => infobox["infobox"].presence || infobox["title"].to_s,
      "url" => url.to_s,
      "content" => infobox["content"].to_s,
      "engine" => infobox["engine"].to_s.presence || "wikipedia"
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
    raise Error, "SearXNG に接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "SearXNG がタイムアウトしました"
  end
end
