# frozen_string_literal: true

require "test_helper"

class SearxngClientTest < ActiveSupport::TestCase
  setup do
    SearxngClient.active_searches = 0
  end

  test "configured when url is present" do
    client = SearxngClient.new(base_url: "http://bowmore.artif.org:8080")

    assert client.configured?
  end

  test "search builds query with engines and default limit from settings" do
    settings = SearxngSettings.from(
      result_count: 3,
      concurrent_searches: 1,
      engines: "duckduckgo,wikipedia",
      retry_count: 0
    )
    client = SearxngClient.new(
      base_url: "http://bowmore.artif.org:8080",
      api_token: "searx_test",
      settings: settings
    )
    requested = []
    client.define_singleton_method(:perform_request) do |uri, req|
      requested << [uri.to_s, req["Accept"], req["Authorization"]]
      SearxngClientTest.fake_http_response(200, {
        query: "ruby rails",
        results: [
          { title: "Ruby on Rails", url: "https://rubyonrails.org", content: "Web framework", engine: "duckduckgo" },
          { title: "Extra", url: "https://example.com", content: "skip me" },
          { title: "Third", url: "https://example.org", content: "third" },
          { title: "Fourth", url: "https://example.net", content: "fourth" }
        ]
      }.to_json)
    end

    result = client.search(q: "ruby rails")

    assert_equal "ruby rails", result["query"]
    assert_equal 3, result["number_of_results"]
    assert_equal "duckduckgo,wikipedia", result["engines"]
    assert_equal "Ruby on Rails", result["results"].first["title"]
    assert_equal 1, requested.size
    assert_includes requested.first[0], "/search?"
    assert_includes requested.first[0], "q=ruby%20rails"
    assert_includes requested.first[0], "engines=duckduckgo%2Cwikipedia"
    assert_equal "application/json", requested.first[1]
    assert_equal "Bearer searx_test", requested.first[2]
  end

  test "includes wikipedia infoboxes when results are empty" do
    settings = SearxngSettings.from(result_count: 5, engines: "wikipedia", retry_count: 0)
    client = SearxngClient.new(base_url: "http://bowmore.artif.org:8080", settings: settings)
    client.define_singleton_method(:perform_request) do |*, **|
      SearxngClientTest.fake_http_response(200, {
        query: "Ruby on Rails",
        results: [],
        infoboxes: [
          {
            infobox: "Ruby on Rails",
            id: "https://en.wikipedia.org/wiki/Ruby_on_Rails",
            content: "A web framework",
            engine: "wikipedia",
            urls: [{ title: "Wikipedia", url: "https://en.wikipedia.org/wiki/Ruby_on_Rails" }]
          }
        ]
      }.to_json)
    end

    result = client.search(q: "Ruby on Rails")

    assert_equal 1, result["number_of_results"]
    assert_equal "Ruby on Rails", result["results"].first["title"]
    assert_equal "https://en.wikipedia.org/wiki/Ruby_on_Rails", result["results"].first["url"]
    assert_equal "wikipedia", result["results"].first["engine"]
  end

  test "retries failed requests up to configured retry count" do
    settings = SearxngSettings.from(result_count: 3, retry_count: 1, engines: "google")
    client = SearxngClient.new(base_url: "http://bowmore.artif.org:8080", settings: settings)
    attempts = 0
    client.define_singleton_method(:perform_request) do |*, **|
      attempts += 1
      if attempts == 1
        SearxngClientTest.fake_http_response(503, { error: "unavailable" }.to_json)
      else
        SearxngClientTest.fake_http_response(200, { query: "test", results: [] }.to_json)
      end
    end
    client.define_singleton_method(:backoff_sleep) { |*| }

    result = client.search(q: "test")

    assert_equal 2, attempts
    assert_equal "test", result["query"]
  end

  test "does not retry 4xx rate limit responses" do
    settings = SearxngSettings.from(retry_count: 2)
    client = SearxngClient.new(base_url: "http://bowmore.artif.org:8080", settings: settings)
    attempts = 0
    client.define_singleton_method(:perform_request) do |*, **|
      attempts += 1
      SearxngClientTest.fake_http_response(429, { error: "too many requests" }.to_json)
    end
    client.define_singleton_method(:backoff_sleep) { |*| }

    error = assert_raises(SearxngClient::Error) { client.search(q: "test") }

    assert_equal 429, error.status
    assert_equal 1, attempts
  end

  test "raises error on api failure when retries exhausted" do
    settings = SearxngSettings.from(retry_count: 0)
    client = SearxngClient.new(base_url: "http://bowmore.artif.org:8080", settings: settings)
    client.define_singleton_method(:perform_request) do |*, **|
      SearxngClientTest.fake_http_response(503, { error: "unavailable" }.to_json)
    end

    error = assert_raises(SearxngClient::Error) { client.search(q: "test") }
    assert_equal "unavailable", error.message
    assert_equal 503, error.status
  end

  def self.fake_http_response(code, body)
    klass = code.to_i.between?(200, 299) ? Net::HTTPOK : Net::HTTPServiceUnavailable
    klass.new("1.1", code.to_s, "OK").tap do |response|
      response.instance_variable_set(:@body, body)
      def response.body = @body
    end
  end
end
