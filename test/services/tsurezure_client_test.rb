# frozen_string_literal: true

require "test_helper"

class TsurezureClientTest < ActiveSupport::TestCase
  setup do
    NyoyConnectionStore.clear_cache!
  end

  test "configured when url and token are present" do
    client = TsurezureClient.new(
      base_url: "https://kbmemo.net",
      api_token: "kbmemo_test"
    )

    assert client.configured?
  end

  test "list_memos builds query and authorization" do
    client = TsurezureClient.new(
      base_url: "https://kbmemo.net",
      api_token: "kbmemo_test"
    )
    requested = []
    client.define_singleton_method(:perform_request) do |uri, req|
      requested << [uri.to_s, req["Authorization"]]
      TsurezureClientTest.fake_http_response(200, { memos: [], pagination: { limit: 10, offset: 0, has_more: false } }.to_json)
    end

    result = client.list_memos(q: "旅行", limit: 10)

    assert_equal [], result["memos"]
    assert_equal 1, requested.size
    assert_includes requested.first[0], "/api/v1/memos?"
    assert_includes requested.first[0], "q=%E6%97%85%E8%A1%8C"
    assert_equal "Bearer kbmemo_test", requested.first[1]
  end

  test "get_memo encodes memo ref" do
    client = TsurezureClient.new(
      base_url: "https://kbmemo.net/api/v1",
      api_token: "kbmemo_test"
    )
    requested = []
    client.define_singleton_method(:perform_request) do |uri, _req|
      requested << uri.to_s
      TsurezureClientTest.fake_http_response(200, { uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX", title: "test", body: "body" }.to_json)
    end

    client.get_memo("01J8X2K3M4N5P6Q7R8S9T0UVWX")

    assert_equal "https://kbmemo.net/api/v1/memos/01J8X2K3M4N5P6Q7R8S9T0UVWX", requested.first
  end

  test "create_memo posts json body" do
    client = TsurezureClient.new(
      base_url: "https://kbmemo.net",
      api_token: "kbmemo_test"
    )
    captured = {}
    client.define_singleton_method(:perform_request) do |uri, req|
      captured[:path] = uri.path
      captured[:body] = JSON.parse(req.body)
      TsurezureClientTest.fake_http_response(201, { uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX", title: "t", body: "b" }.to_json)
    end

    client.create_memo(title: "タイトル", body: "## 見出し\n\n本文")

    assert_equal "/api/v1/memos", captured[:path]
    assert_equal "タイトル", captured[:body]["title"]
    assert_equal "## 見出し\n\n本文", captured[:body]["body"]
    assert captured[:body]["commit"]
  end

  test "export_memos builds export query" do
    client = TsurezureClient.new(
      base_url: "https://kbmemo.net",
      api_token: "kbmemo_test"
    )
    requested = []
    client.define_singleton_method(:perform_request) do |uri, _req|
      requested << uri.to_s
      TsurezureClientTest.fake_http_response(200, { memos: [], pagination: { limit: 100, has_more: false } }.to_json)
    end

    client.export_memos(updated_since: Time.utc(2026, 7, 1, 0, 0, 0), cursor: "abc", limit: 50)

    assert_equal 1, requested.size
    assert_includes requested.first, "/api/v1/memos/export?"
    assert_includes requested.first, "updated_since="
    assert_includes requested.first, "cursor=abc"
    assert_includes requested.first, "limit=50"
  end

  test "raises error on api failure" do
    client = TsurezureClient.new(
      base_url: "https://kbmemo.net",
      api_token: "kbmemo_test"
    )
    client.define_singleton_method(:perform_request) do |*, **|
      TsurezureClientTest.fake_http_response(401, { error: { code: "unauthorized", message: "認証に失敗しました。" } }.to_json)
    end

    error = assert_raises(TsurezureClient::Error) { client.get_memo("42") }
    assert_equal "認証に失敗しました。", error.message
    assert_equal 401, error.status
  end

  def self.fake_http_response(code, body)
    klass = code.to_i.between?(200, 299) ? Net::HTTPOK : Net::HTTPUnauthorized
    klass.new("1.1", code.to_s, "OK").tap do |response|
      response.instance_variable_set(:@body, body)
      def response.body = @body
    end
  end
end
