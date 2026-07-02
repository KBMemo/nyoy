# frozen_string_literal: true

require "test_helper"

class ChatToolsConnectionRefreshTest < ActiveSupport::TestCase
  test "searxng client uses url updated in service connection" do
    connection = service_connections(:searxng)
    connection.update!(base_url: "http://updated-searx:8080", api_token: "fresh_token")

    requested = []
    client = ChatTools::Registry.searxng_client
    client.define_singleton_method(:perform_request) do |uri, req|
      requested << [uri.to_s, req["Authorization"]]
      ChatToolsConnectionRefreshTest.fake_http_response(200, { results: [] }.to_json)
    end

    client.search(q: "test")

    assert_equal 1, requested.size
    assert_includes requested.first[0], "http://updated-searx:8080/search"
    assert_equal "Bearer fresh_token", requested.first[1]
  end

  test "service connection save clears chat tool clients" do
    called = false
    original_reset = ChatTools::Registry.method(:reset_client!)
    ChatTools::Registry.define_singleton_method(:reset_client!) { called = true }

    service_connections(:searxng).update!(base_url: "http://another-searx:8080")

    assert called
  ensure
    ChatTools::Registry.define_singleton_method(:reset_client!, original_reset)
  end

  def self.fake_http_response(code, body)
    Net::HTTPOK.new("1.1", code.to_s, "OK").tap do |response|
      response.instance_variable_set(:@body, body)
      def response.body = @body
    end
  end
end
