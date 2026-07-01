# frozen_string_literal: true

require "test_helper"

class ServiceConnectionModelFetcherTest < ActiveSupport::TestCase
  test "fetches openai compatible model ids" do
    connection = service_connections(:gpt_oss)
    fetcher = ServiceConnectionModelFetcher.new(connection)
    requested = []
    fetcher.define_singleton_method(:perform_get) do |uri, **|
      requested << uri.to_s
      { status: 200, body: { data: [{ id: "gpt-oss-20b" }, { id: "gpt-oss-120b" }] }.to_json }
    end

    result = fetcher.call

    assert result.ok
    assert_equal ["http://balvenie:10010/v1/models"], requested
    assert_equal %w[gpt-oss-20b gpt-oss-120b], result.models
    assert_match(/モデル 2 件/, result.message)
  end

  test "reports unsupported connection type" do
    connection = service_connections(:sd_cpp)

    result = ServiceConnectionModelFetcher.new(connection).call

    assert_not result.ok
    assert_equal [], result.models
    assert_match(/対応していません/, result.message)
  end

  test "reports invalid json" do
    connection = service_connections(:llama_cpp)
    fetcher = ServiceConnectionModelFetcher.new(connection)
    fetcher.define_singleton_method(:perform_get) do |*, **|
      { status: 200, body: "not json" }
    end

    result = fetcher.call

    assert_not result.ok
    assert_match(/JSON/, result.message)
  end
end
