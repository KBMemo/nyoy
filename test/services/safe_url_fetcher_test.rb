# frozen_string_literal: true

require "test_helper"

class SafeUrlFetcherTest < ActiveSupport::TestCase
  setup do
    @fetcher = SafeUrlFetcher.new
  end

  test "rejects non-http schemes" do
    error = assert_raises(SafeUrlFetcher::Error) { @fetcher.fetch("file:///etc/passwd") }
    assert_equal "http または https の URL を指定してください", error.message
  end

  test "rejects pdf urls" do
    error = assert_raises(SafeUrlFetcher::Error) { @fetcher.fetch("https://example.com/report.pdf") }
    assert_equal "PDF は現在取得対象外です", error.message
  end

  test "accepts japanese path urls as valid iris" do
    paths = []
    disabled_readability = Object.new
    disabled_readability.define_singleton_method(:configured?) { false }
    fetcher = SafeUrlFetcher.new(readability_client: disabled_readability)
    fetcher.define_singleton_method(:perform_get) do |uri|
      paths << uri.path
      SafeUrlFetcherTest.fake_http_response(
        200,
        "<html><head><title>元三大師</title></head><body><p>良源</p></body></html>",
        uri: uri,
        content_type: "text/html; charset=utf-8"
      )
    end

    result = fetcher.fetch("https://ja.wikipedia.org/wiki/元三大師")

    assert_includes paths, "/wiki/%E5%85%83%E4%B8%89%E5%A4%A7%E5%B8%AB"
    assert_equal "https://ja.wikipedia.org/wiki/%E5%85%83%E4%B8%89%E5%A4%A7%E5%B8%AB", result[:url]
    assert_equal "元三大師", result[:title]
    assert_includes result[:text], "良源"
  end

  test "rejects pdf content type responses" do
    @fetcher.define_singleton_method(:perform_get) do |uri|
      SafeUrlFetcherTest.fake_http_response(
        200,
        "%PDF-1.4",
        uri: uri,
        content_type: "application/pdf"
      )
    end

    error = assert_raises(SafeUrlFetcher::Error) { @fetcher.fetch("https://example.com/download") }
    assert_equal "PDF は現在取得対象外です", error.message
  end

  test "rejects localhost" do
    error = assert_raises(SafeUrlFetcher::Error) { @fetcher.fetch("http://localhost/secret") }
    assert_equal "このホストにはアクセスできません", error.message
  end

  test "rejects private ip addresses" do
    error = assert_raises(SafeUrlFetcher::Error) { @fetcher.fetch("http://192.168.1.10/page") }
    assert_equal "プライベートネットワークのアドレスにはアクセスできません", error.message
  end

  test "rejects private addresses resolved from hostname" do
    @fetcher.define_singleton_method(:validate_host!) do |_host|
      raise SafeUrlFetcher::Error, "プライベートネットワークのアドレスにはアクセスできません"
    end

    error = assert_raises(SafeUrlFetcher::Error) { @fetcher.fetch("http://evil.example/page") }
    assert_equal "プライベートネットワークのアドレスにはアクセスできません", error.message
  end

  test "fetches html and extracts text" do
    disabled_readability = Object.new
    disabled_readability.define_singleton_method(:configured?) { false }
    fetcher = SafeUrlFetcher.new(readability_client: disabled_readability)
    fetcher.define_singleton_method(:perform_get) do |uri|
      SafeUrlFetcherTest.fake_http_response(
        200,
        "<html><head><title>Example</title></head><body><h1>Hello</h1><script>bad()</script></body></html>",
        uri: uri,
        content_type: "text/html; charset=utf-8"
      )
    end

    result = fetcher.fetch("https://example.com/page")

    assert_equal "https://example.com/page", result[:url]
    assert_equal 200, result[:status]
    assert_equal "Example", result[:title]
    assert_includes result[:text], "Hello"
    assert_not_includes result[:text], "bad()"
  end

  test "uses readability when configured" do
    fake_client = Object.new
    fake_client.define_singleton_method(:configured?) { true }
    fake_client.define_singleton_method(:extract) do |url|
      {
        "url" => url,
        "title" => "白百合学園",
        "textContent" => "ようこそ。学校案内です。"
      }
    end

    fetcher = SafeUrlFetcher.new(readability_client: fake_client)
    fetcher.define_singleton_method(:perform_get) do |uri|
      raise "should not fetch HTML directly"
    end

    result = fetcher.fetch("https://www.shirayuri-ikehara.com/")

    assert_equal "readability", result[:extractor]
    assert_equal "白百合学園", result[:title]
    assert_includes result[:text], "学校案内"
  end

  test "include_full_text keeps full body out of preview text" do
    fake_client = Object.new
    fake_client.define_singleton_method(:configured?) { true }
    fake_client.define_singleton_method(:extract) do |url|
      {
        "url" => url,
        "title" => "Long",
        "textContent" => "あ" * 500
      }
    end

    fetcher = SafeUrlFetcher.new(readability_client: fake_client)
    fetcher.define_singleton_method(:perform_get) { raise "should not fetch HTML directly" }

    result = fetcher.fetch("https://example.com/long", max_bytes: 100, include_full_text: true)

    assert result[:truncated]
    assert_operator result[:text].bytesize, :<=, 100
    assert_operator result[:full_text].bytesize, :>, 100
  end

  test "falls back to direct fetch when readability fails" do
    fake_client = Object.new
    fake_client.define_singleton_method(:configured?) { true }
    fake_client.define_singleton_method(:extract) do |_url|
      raise ReadabilityClient::Error, "upstream failed"
    end

    fetcher = SafeUrlFetcher.new(readability_client: fake_client)
    fetcher.define_singleton_method(:perform_get) do |uri|
      SafeUrlFetcherTest.fake_http_response(
        200,
        "<html><head><title>Fallback</title></head><body><p>Direct</p></body></html>",
        uri: uri,
        content_type: "text/html; charset=utf-8"
      )
    end

    result = fetcher.fetch("https://example.com/page")

    assert_nil result[:extractor]
    assert_equal "Fallback", result[:title]
    assert_includes result[:text], "Direct"
  end

  test "fetches site root without invalid markdown alternate path" do
    calls = []
    disabled_readability = Object.new
    disabled_readability.define_singleton_method(:configured?) { false }
    fetcher = SafeUrlFetcher.new(readability_client: disabled_readability)
    fetcher.define_singleton_method(:perform_get) do |uri|
      calls << uri.path
      SafeUrlFetcherTest.fake_http_response(
        200,
        "<html><head><title>白百合学園</title></head><body><p>ようこそ</p></body></html>",
        uri: uri,
        content_type: "text/html; charset=utf-8"
      )
    end

    result = fetcher.fetch("https://www.shirayuri-ikehara.com/")

    assert_equal ["/"], calls
    assert_equal "https://www.shirayuri-ikehara.com/", result[:url]
    assert_equal 200, result[:status]
    assert_equal "白百合学園", result[:title]
    assert_includes result[:text], "ようこそ"
  end

  test "does not probe a .md alternate and prefers readability" do
    fake_client = Object.new
    fake_client.define_singleton_method(:configured?) { true }
    fake_client.define_singleton_method(:extract) do |url|
      {
        "url" => url,
        "title" => "LangChain overview",
        "textContent" => "Agent = Model + Harness."
      }
    end

    calls = []
    fetcher = SafeUrlFetcher.new(readability_client: fake_client)
    fetcher.define_singleton_method(:perform_get) do |uri|
      calls << uri.path
      SafeUrlFetcherTest.fake_http_response(200, "<html></html>", uri: uri, content_type: "text/html")
    end

    result = fetcher.fetch("https://docs.langchain.com/oss/python/langchain/overview")

    assert_empty calls
    assert_equal "readability", result[:extractor]
    assert_includes result[:text], "Agent = Model + Harness"
  end

  test "does not probe a .md alternate before direct fetch" do
    calls = []
    disabled_readability = Object.new
    disabled_readability.define_singleton_method(:configured?) { false }
    fetcher = SafeUrlFetcher.new(readability_client: disabled_readability)
    fetcher.define_singleton_method(:perform_get) do |uri|
      calls << uri.path
      SafeUrlFetcherTest.fake_http_response(
        200,
        "<html><head><title>Overview</title></head><body><p>Direct</p></body></html>",
        uri: uri,
        content_type: "text/html; charset=utf-8"
      )
    end

    result = fetcher.fetch("https://docs.langchain.com/oss/python/langchain/overview")

    assert_equal ["/oss/python/langchain/overview"], calls
    assert_includes result[:text], "Direct"
  end

  test "truncates text on a valid utf-8 boundary" do
    disabled_readability = Object.new
    disabled_readability.define_singleton_method(:configured?) { false }
    fetcher = SafeUrlFetcher.new(readability_client: disabled_readability)
    fetcher.define_singleton_method(:perform_get) do |uri|
      SafeUrlFetcherTest.fake_http_response(
        200,
        "<html><body>#{'あ' * 500}</body></html>",
        uri: uri,
        content_type: "text/html; charset=utf-8"
      )
    end

    result = fetcher.fetch("https://example.com/page.html", max_bytes: 100)

    assert result[:text].valid_encoding?
    assert_operator result[:text].bytesize, :<=, 100
  end

  test "truncates oversized html instead of erroring" do
    fetcher = SafeUrlFetcher.new(max_body_bytes: 500_000)
    fetcher.define_singleton_method(:perform_get) do |uri|
      SafeUrlFetcherTest.fake_http_response(
        200,
        "<html><head><title>Big</title></head><body>#{'word ' * 300_000}</body></html>",
        uri: uri,
        content_type: "text/html; charset=utf-8"
      )
    end

    result = fetcher.fetch("https://example.com/big-page.html")

    assert_equal 200, result[:status]
    assert result[:truncated]
    assert result[:text].present?
  end

  test "follows redirects with validation" do
    calls = []
    disabled_readability = Object.new
    disabled_readability.define_singleton_method(:configured?) { false }
    fetcher = SafeUrlFetcher.new(readability_client: disabled_readability)
    fetcher.define_singleton_method(:perform_get) do |uri|
      calls << uri.to_s
      if uri.path == "/start"
        SafeUrlFetcherTest.fake_http_response(302, "", uri: uri, location: "/final")
      else
        SafeUrlFetcherTest.fake_http_response(200, "plain text", uri: uri, content_type: "text/plain")
      end
    end

    result = fetcher.fetch("https://example.com/start")

    assert_includes calls, "https://example.com/start"
    assert_includes calls, "https://example.com/final"
    assert_equal "plain text", result[:text]
  end

  def self.fake_http_response(code, body, uri:, content_type: nil, location: nil)
    klass = case code.to_i
            when 200..299 then Net::HTTPOK
            when 300..399 then Net::HTTPFound
            when 404 then Net::HTTPNotFound
            else Net::HTTPBadRequest
            end
    klass.new("1.1", code.to_s, "OK").tap do |response|
      response.instance_variable_set(:@body, body)
      response["content-type"] = content_type if content_type
      response["location"] = location if location
      response.singleton_class.attr_accessor :uri
      response.uri = uri
      def response.body = @body
    end
  end
end
