# frozen_string_literal: true

require "cgi"
require "ipaddr"
require "net/http"
require "resolv"
require "uri"

class SafeUrlFetcher
  class Error < StandardError; end

  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 15
  MAX_REDIRECTS = 3
  MAX_BODY_BYTES = 2_097_152
  USER_AGENT = "NyoyBot/1.0 (+https://kbmemo.net)"

  PRIVATE_IP_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.0.0.0/24"),
    IPAddr.new("192.0.2.0/24"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("198.18.0.0/15"),
    IPAddr.new("240.0.0.0/4"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10")
  ].freeze

  BLOCKED_HOST_SUFFIXES = %w[.local .internal .localhost .localdomain].freeze

  @fetch_mutex = Mutex.new
  @active_fetches = 0
  @fetch_condition = ConditionVariable.new

  class << self
    attr_reader :fetch_mutex, :fetch_condition

    def active_fetches
      @active_fetches
    end

    def active_fetches=(value)
      @active_fetches = value
    end
  end

  def initialize(
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT,
    max_body_bytes: MAX_BODY_BYTES,
    readability_client: nil
  )
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @max_body_bytes = max_body_bytes
    @readability_client = readability_client
  end

  def fetch(url, max_bytes: 6_000, include_full_text: false)
    with_concurrency_limit(concurrent_fetch_limit) do
      fetch_without_concurrency_limit(url, max_bytes: max_bytes, include_full_text: include_full_text)
    end
  end

  private

  def fetch_without_concurrency_limit(url, max_bytes:, include_full_text:)
    uri = parse_public_http_url!(url)
    reject_pdf_url!(uri)

    readability_result = fetch_via_readability(uri, max_bytes: max_bytes, include_full_text: include_full_text)
    return readability_result if readability_result

    fetch_response(uri, max_bytes: max_bytes, include_full_text: include_full_text)
  end

  def concurrent_fetch_limit
    SearxngSettings.load.concurrent_fetches
  end

  def with_concurrency_limit(limit)
    self.class.fetch_mutex.synchronize do
      while self.class.active_fetches >= limit
        self.class.fetch_condition.wait(self.class.fetch_mutex)
      end
      self.class.active_fetches += 1
    end

    yield
  ensure
    self.class.fetch_mutex.synchronize do
      self.class.active_fetches -= 1
      self.class.fetch_condition.signal
    end
  end

  def fetch_via_readability(uri, max_bytes:, include_full_text: false)
    client = @readability_client || default_readability_client
    return nil unless client.configured?

    payload = client.extract(uri.to_s)
    full_text = readability_text(payload)
    return nil if full_text.blank?

    preview_text, truncated = limit_text_bytes(full_text, max_bytes)

    {
      url: utf8_string(payload["url"].presence || uri.to_s),
      status: 200,
      title: utf8_string(payload["title"]).presence,
      text: preview_text,
      full_text: include_full_text ? utf8_string(full_text) : nil,
      excerpt: utf8_string(payload["excerpt"]).presence,
      byline: utf8_string(payload["byline"]).presence,
      site_name: utf8_string(payload["siteName"]).presence,
      extractor: "readability",
      truncated: truncated || nil
    }.compact
  rescue ReadabilityClient::Error
    nil
  end

  def default_readability_client
    @default_readability_client ||= ReadabilityClient.new
  end

  def readability_text(payload)
    utf8_string(payload["textContent"]).presence ||
      utf8_string(markdown_to_text(payload["content"].to_s).squish).presence
  end

  def fetch_response(uri, max_bytes:, include_full_text: false)
    response = follow_redirects(uri)
    reject_pdf_response!(response)
    body, body_truncated = read_limited_body(response)
    content_type = response["content-type"].to_s
    full_text = extract_text(body, content_type)
    preview_text, text_truncated = limit_text_bytes(full_text, max_bytes)

    {
      url: response.uri.to_s,
      status: response.code.to_i,
      content_type: content_type,
      title: utf8_string(extract_title(body)).presence,
      text: preview_text,
      full_text: include_full_text ? utf8_string(full_text) : nil,
      truncated: (body_truncated || text_truncated) || nil
    }.compact
  end

  def reject_pdf_url!(uri)
    raise Error, "PDF は現在取得対象外です" if PdfUrl.blocked?(uri.to_s)
  end

  def reject_pdf_response!(response)
    raise Error, "PDF は現在取得対象外です" if PdfUrl.blocked?(response.uri.to_s)
    raise Error, "PDF は現在取得対象外です" if PdfUrl.blocked_content_type?(response["content-type"])
  end

  def parse_public_http_url!(url)
    uri = HttpUrl.parse(url)
    raise Error, "http または https の URL を指定してください" unless uri.is_a?(URI::HTTP)

    uri.host = uri.host.to_s.downcase
    validate_host!(uri.host)
    uri
  rescue URI::InvalidURIError
    raise Error, "URL の形式が不正です"
  end

  def validate_host!(host)
    raise Error, "ホスト名がありません" if host.blank?
    raise Error, "このホストにはアクセスできません" if blocked_hostname?(host)

    Resolv.getaddresses(host).each do |address|
      raise Error, "プライベートネットワークのアドレスにはアクセスできません" if private_ip?(address)
    end
  rescue Resolv::ResolvError
    raise Error, "ホスト名を解決できませんでした"
  end

  def blocked_hostname?(host)
    normalized = host.downcase
    return true if normalized == "localhost"
    return true if normalized.end_with?(*BLOCKED_HOST_SUFFIXES)

    normalized.include?("metadata.google")
  end

  def private_ip?(address)
    ip = IPAddr.new(address)
    PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def follow_redirects(uri)
    current = uri
    redirects = 0

    loop do
      response = perform_get(current)
      return response if redirect_response?(response) == false

      location = response["location"]
      raise Error, "リダイレクト先が不正です" if location.blank?

      redirects += 1
      raise Error, "リダイレクトが多すぎます" if redirects > MAX_REDIRECTS

      current = parse_public_http_url!(URI.join(current, location).to_s)
    end
  end

  def redirect_response?(response)
    response.is_a?(Net::HTTPRedirection)
  end

  def perform_get(uri)
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT
    req["Accept"] = "text/markdown,text/plain,text/html,application/xhtml+xml;q=0.9"

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.use_ssl = uri.scheme == "https"
    response = http.request(req)
    response.singleton_class.attr_accessor :uri
    response.uri = uri
    response
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "URL に接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "URL の取得がタイムアウトしました"
  end

  def read_limited_body(response)
    if response.body.present?
      body = response.body
      return truncate_body(body) if body.bytesize > @max_body_bytes

      return [body, false]
    end

    collect_streaming_body(response)
  rescue Net::HTTPBadResponse, Net::ReadTimeout, IOError => e
    raise Error, "レスポンスの読み取りに失敗しました（#{e.message}）"
  end

  def collect_streaming_body(response)
    body = +""
    truncated = false

    response.read_body do |chunk|
      remaining = @max_body_bytes - body.bytesize
      if chunk.bytesize > remaining
        body << chunk.byteslice(0, remaining)
        truncated = true
        break
      end

      body << chunk
    end

    [body, truncated]
  end

  def truncate_body(body)
    [body.byteslice(0, @max_body_bytes), true]
  end

  def extract_title(body)
    match = body.match(%r{<title[^>]*>(.*?)</title>}im)
    return decode_entities(match[1]).squish.presence if match

    heading = body.match(/^#\s+(.+)$/m)
    decode_entities(heading[1]).squish.presence if heading
  end

  def extract_text(body, content_type)
    text = if markdown_content?(content_type, body)
             markdown_to_text(body)
           elsif html_content?(content_type, body)
             html_to_text(body)
           else
             body.to_s
           end

    text.squish
  end

  def limit_text_bytes(text, max_bytes)
    utf8 = utf8_string(text)
    return [utf8, false] if utf8.bytesize <= max_bytes

    [truncate_text(utf8, max_bytes), true]
  end

  # Byte-based truncation that never leaves a broken multibyte tail. HTTP /
  # readability bodies often arrive as ASCII-8BIT; scrub only works after
  # force_encoding UTF-8 (BINARY treats every byte as valid).
  def truncate_text(text, max_bytes)
    utf8 = utf8_string(text)
    return utf8 if utf8.bytesize <= max_bytes

    utf8_string(utf8.byteslice(0, max_bytes))
  end

  def utf8_string(value)
    return "" if value.nil?

    value.to_s.dup.force_encoding(Encoding::UTF_8).scrub("")
  end

  def markdown_content?(content_type, body)
    return true if content_type.include?("text/markdown") || content_type.include?("text/x-markdown")

    body.lstrip.start_with?("#", ">")
  end

  def html_content?(content_type, body)
    content_type.include?("text/html") || body.include?("<html")
  end

  def markdown_to_text(body)
    text = body.to_s.dup
    text.gsub!(/<[^>]+>/, " ")
    decode_entities(text)
  end

  def html_to_text(html)
    text = html.to_s.dup
    text.gsub!(%r{<script[^>]*>.*?</script>}im, " ")
    text.gsub!(%r{<style[^>]*>.*?</style>}im, " ")
    text.gsub!(%r{<!--.*?-->}m, " ")
    text.gsub!(/<[^>]+>/, " ")
    decode_entities(text)
  end

  def decode_entities(text)
    CGI.unescapeHTML(text.to_s)
  end
end
