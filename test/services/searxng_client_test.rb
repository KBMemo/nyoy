# frozen_string_literal: true

require "test_helper"

class SearxngClientTest < ActiveSupport::TestCase
  test "configured when url is present" do
    client = SearxngClient.new(base_url: "http://bowmore.artif.org:8080")

    assert client.configured?
  end

  test "search builds query and normalizes results" do
    client = SearxngClient.new(base_url: "http://bowmore.artif.org:8080", api_token: "searx_test")
    requested = []
    client.define_singleton_method(:perform_request) do |uri, req|
      requested << [uri.to_s, req["Accept"], req["Authorization"]]
      SearxngClientTest.fake_http_response(200, {
        query: "ruby rails",
        results: [
          { title: "Ruby on Rails", url: "https://rubyonrails.org", content: "Web framework", engine: "google" },
          { title: "Extra", url: "https://example.com", content: "skip me" }
        ]
      }.to_json)
    end

    result = client.search(q: "ruby rails", limit: 1)

    assert_equal "ruby rails", result["query"]
    assert_equal 1, result["number_of_results"]
    assert_equal "Ruby on Rails", result["results"].first["title"]
    assert_equal 1, requested.size
    assert_includes requested.first[0], "/search?"
    assert_includes requested.first[0], "q=ruby%20rails"
    assert_equal "application/json", requested.first[1]
    assert_equal "Bearer searx_test", requested.first[2]
  end

  test "raises error on api failure" do
    client = SearxngClient.new(base_url: "http://bowmore.artif.org:8080")
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
