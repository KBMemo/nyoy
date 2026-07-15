# frozen_string_literal: true

require "test_helper"

class SearfrontClientTest < ActiveSupport::TestCase
  setup do
    SearfrontClient.active_searches = 0
  end

  test "configured only when url and token are present" do
    assert_not SearfrontClient.new(base_url: "http://bowmore:13000", api_token: "").configured?
    assert SearfrontClient.new(base_url: "http://bowmore:13000", api_token: "tok").configured?
  end

  test "search hits /v1/search and maps snippet to content" do
    settings = SearfrontSettings.from(result_count: 2, concurrent_searches: 1, retry_count: 0)
    client = SearfrontClient.new(
      base_url: "http://bowmore:13000",
      api_token: "searfront_test",
      settings: settings,
      wait_seconds: 8
    )
    requested = []
    client.define_singleton_method(:perform_request) do |uri, req|
      requested << [uri.to_s, req["Authorization"]]
      SearfrontClientTest.fake_http_response(200, {
        request_id: "req-1",
        status: "completed",
        query: "ruby rails",
        normalized_query: "ruby rails",
        sources: [ "exa" ],
        cache: { status: "fresh" },
        warnings: [],
        results: [
          {
            title: "Ruby on Rails",
            url: "https://rubyonrails.org",
            snippet: "Web framework",
            engines: [ "exa" ],
            source: "exa",
            rank: 1
          },
          {
            title: "Extra",
            url: "https://example.com",
            snippet: "skip? no keep within limit",
            engines: [ "exa" ],
            rank: 2
          },
          {
            title: "Third",
            url: "https://example.org",
            snippet: "third",
            engines: [ "exa" ],
            rank: 3
          }
        ]
      }.to_json)
    end

    result = client.search(q: "ruby rails")

    assert_equal "ruby rails", result["query"]
    assert_equal 2, result["number_of_results"]
    assert_equal "exa", result["engines"]
    assert_equal "Ruby on Rails", result["results"].first["title"]
    assert_equal "Web framework", result["results"].first["content"]
    assert_equal "exa", result["results"].first["engine"]
    assert_equal 1, requested.size
    assert_includes requested.first[0], "/v1/search?"
    assert_includes requested.first[0], "q=ruby%20rails"
    assert_includes requested.first[0], "limit=2"
    assert_includes requested.first[0], "wait_seconds=8"
    assert_equal "Bearer searfront_test", requested.first[1]
  end

  test "polls search_requests when search returns 202" do
    settings = SearfrontSettings.from(result_count: 1, retry_count: 0)
    client = SearfrontClient.new(
      base_url: "http://bowmore:13000",
      api_token: "tok",
      settings: settings,
      wait_seconds: 0
    )
    calls = []
    client.define_singleton_method(:backoff_sleep) { |*| }
    client.define_singleton_method(:perform_request) do |uri, _req|
      calls << uri.to_s
      if uri.path == "/v1/search"
        SearfrontClientTest.fake_http_response(202, {
          request_id: "req-pending",
          status: "pending",
          poll_after_seconds: 1,
          warnings: [ "browser_fallback_queued" ]
        }.to_json)
      else
        SearfrontClientTest.fake_http_response(200, {
          request_id: "req-pending",
          status: "completed",
          query: "test",
          sources: [ "browser" ],
          results: [
            { title: "Ok", url: "https://example.com", snippet: "done", engines: [ "google" ] }
          ]
        }.to_json)
      end
    end

    result = client.search(q: "test")

    assert_equal 2, calls.size
    assert_includes calls.first, "/v1/search?"
    assert_includes calls.last, "/v1/search_requests/req-pending"
    assert_equal 1, result["number_of_results"]
    assert_equal "done", result["results"].first["content"]
    assert_equal "google", result["results"].first["engine"]
  end

  test "retries 5xx up to configured retry count" do
    settings = SearfrontSettings.from(result_count: 1, retry_count: 1)
    client = SearfrontClient.new(base_url: "http://bowmore:13000", api_token: "tok", settings: settings)
    attempts = 0
    client.define_singleton_method(:backoff_sleep) { |*| }
    client.define_singleton_method(:perform_request) do |*, **|
      attempts += 1
      if attempts == 1
        SearfrontClientTest.fake_http_response(503, { error: { code: "unavailable", message: "down" } }.to_json)
      else
        SearfrontClientTest.fake_http_response(200, {
          status: "completed",
          query: "test",
          sources: [],
          results: [ { title: "Ok", url: "https://example.com", snippet: "ok", engines: [ "exa" ] } ]
        }.to_json)
      end
    end

    result = client.search(q: "test")

    assert_equal 2, attempts
    assert_equal 1, result["number_of_results"]
  end

  test "does not retry 4xx" do
    settings = SearfrontSettings.from(retry_count: 2)
    client = SearfrontClient.new(base_url: "http://bowmore:13000", api_token: "tok", settings: settings)
    attempts = 0
    client.define_singleton_method(:backoff_sleep) { |*| }
    client.define_singleton_method(:perform_request) do |*, **|
      attempts += 1
      SearfrontClientTest.fake_http_response(401, { error: { code: "unauthorized", message: "bad token" } }.to_json)
    end

    error = assert_raises(SearfrontClient::Error) { client.search(q: "test") }

    assert_equal 401, error.status
    assert_equal "bad token", error.message
    assert_equal 1, attempts
  end

  def self.fake_http_response(code, body)
    klass =
      case code.to_i
      when 200 then Net::HTTPOK
      when 202 then Net::HTTPAccepted
      when 401 then Net::HTTPUnauthorized
      else Net::HTTPServiceUnavailable
      end
    klass.new("1.1", code.to_s, "OK").tap do |response|
      response.instance_variable_set(:@body, body)
      def response.body = @body
    end
  end
end
