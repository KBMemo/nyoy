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

  def initialize(
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT,
    max_body_bytes: MAX_BODY_BYTES
  )
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @max_body_bytes = max_body_bytes
  end

  def fetch(url, max_chars: 12_000)
    uri = parse_public_http_url!(url)
    markdown_uri = markdown_alternate_uri(uri)

    if markdown_uri
      result = fetch_response(markdown_uri, max_chars: max_chars)
      return result if result[:status] == 200 && result[:text].present?
    end

    fetch_response(uri, max_chars: max_chars)
  end

  private

  def fetch_response(uri, max_chars:)
    response = follow_redirects(uri)
    body, truncated = read_limited_body(response)
    content_type = response["content-type"].to_s

    {
      url: response.uri.to_s,
      status: response.code.to_i,
      content_type: content_type,
      title: extract_title(body),
      text: extract_text(body, content_type, max_chars: max_chars),
      truncated: truncated || nil
    }.compact
  end

  def markdown_alternate_uri(uri)
    return nil if uri.path.match?(/\.[a-zA-Z0-9]+\z/)

    alternate = uri.dup
    alternate.path = "#{uri.path.chomp('/')}.md"
    alternate
  end

  def parse_public_http_url!(url)
    uri = URI.parse(url.to_s.strip)
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
    req["Accept"] = "text/markdown,text/plain,text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"

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

  def extract_text(body, content_type, max_chars:)
    text = if markdown_content?(content_type, body)
             markdown_to_text(body)
           elsif html_content?(content_type, body)
             html_to_text(body)
           else
             body.to_s
           end

    text = text.squish
    text = text.byteslice(0, max_chars) if text.bytesize > max_chars
    text
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
