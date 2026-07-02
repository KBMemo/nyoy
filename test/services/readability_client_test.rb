# frozen_string_literal: true

require "test_helper"

class ReadabilityClientTest < ActiveSupport::TestCase
  setup do
    NyoyConnectionStore.clear_cache!
  end

  test "configured when url is present and connection enabled" do
    client = ReadabilityClient.new(base_url: "http://bowmore:8030")

    assert client.configured?
  end

  test "extract posts url and content format" do
    client = ReadabilityClient.new(base_url: "http://bowmore:8030")
    captured = {}
    client.define_singleton_method(:post_json) do |path, payload|
      captured[:path] = path
      captured[:payload] = payload
      {
        "url" => payload[:url],
        "title" => "Example",
        "textContent" => "Article body"
      }
    end

    result = client.extract("https://example.com/page")

    assert_equal "/", captured[:path]
    assert_equal "https://example.com/page", captured[:payload][:url]
    assert_equal "markdown", captured[:payload][:contentFormat]
    assert_equal "Article body", result["textContent"]
  end

  test "raises error on api failure" do
    client = ReadabilityClient.new(base_url: "http://bowmore:8030")
    client.define_singleton_method(:post_json) do |*, **|
      raise ReadabilityClient::Error.new("Fetch request timed out", status: 500, code: "FETCH_TIMEOUT")
    end

    error = assert_raises(ReadabilityClient::Error) { client.extract("https://example.com") }
    assert_equal "Fetch request timed out", error.message
    assert_equal "FETCH_TIMEOUT", error.code
  end
end
