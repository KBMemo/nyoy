# frozen_string_literal: true

require "test_helper"

class TsuzuraClientTest < ActiveSupport::TestCase
  setup do
    NyoyConnectionStore.clear_cache!
  end

  test "configured when url and token present" do
    client = TsuzuraClient.new(
      base_url: "http://localhost:3008",
      api_token: "tsuzura_test"
    )

    assert client.configured?
  end

  test "normalizes api root to v1" do
    client = TsuzuraClient.new(
      base_url: "http://localhost:3008",
      api_token: "tsuzura_test"
    )

    assert_equal "http://localhost:3008/v1", client.send(:normalize_api_root, "http://localhost:3008")
    assert_equal "http://localhost:3008/v1", client.send(:normalize_api_root, "http://localhost:3008/v1")
  end

  test "list_albums returns albums from api" do
    client = TsuzuraClient.new(
      base_url: "http://localhost:3008",
      api_token: "tsuzura_test"
    )
    requested = []
    client.define_singleton_method(:perform_request) do |uri, req|
      requested << [uri.to_s, req["Authorization"]]
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@body, { albums: [{ id: "01JTEST", title: "Nyoy Chat" }] }.to_json)
      def response.body = @body
      response
    end

    result = client.list_albums

    assert_equal 1, result.fetch("albums").size
    assert_equal "http://localhost:3008/v1/albums", requested.first[0]
    assert_equal "Bearer tsuzura_test", requested.first[1]
  end

  test "get_media returns item payload" do
    client = TsuzuraClient.new(
      base_url: "http://localhost:3008",
      api_token: "tsuzura_test"
    )
    client.define_singleton_method(:perform_request) do |*, **|
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@body, { id: "01JTEST", original_filename: "photo.png" }.to_json)
      def response.body = @body
      response
    end

    result = client.get_media("01JTEST")

    assert_equal "01JTEST", result["id"]
    assert_equal "photo.png", result["original_filename"]
  end

  test "download_media returns binary payload" do
    client = TsuzuraClient.new(
      base_url: "http://localhost:3008",
      api_token: "tsuzura_test"
    )
    requested = []
    client.define_singleton_method(:perform_request) do |uri, req|
      requested << [uri.to_s, req["Authorization"]]
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response["Content-Type"] = "image/png"
      response["Content-Disposition"] = 'inline; filename="photo.png"'
      response.instance_variable_set(:@body, "png-bytes")
      def response.body = @body
      response
    end

    result = client.download_media("01JTEST")

    assert_equal "http://localhost:3008/v1/media/01JTEST/file", requested.first[0]
    assert_equal "Bearer tsuzura_test", requested.first[1]
    assert_equal "png-bytes", result.data
    assert_equal "image/png", result.content_type
    assert_equal "photo.png", result.filename
  end
end
