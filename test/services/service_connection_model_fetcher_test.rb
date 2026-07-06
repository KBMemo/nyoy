# frozen_string_literal: true

require "test_helper"

class ServiceConnectionModelFetcherTest < ActiveSupport::TestCase
  test "fetches openai api models with bearer token and filters chat models" do
    connection = service_connections(:openai)
    connection.update!(api_token: "sk-test")
    fetcher = ServiceConnectionModelFetcher.new(connection)
    requested = []
    fetcher.define_singleton_method(:perform_get) do |uri, headers: {}, **|
      requested << [uri.to_s, headers["Authorization"]]
      {
        status: 200,
        body: {
          data: [
            { id: "gpt-4o" },
            { id: "whisper-1" },
            { id: "gpt-4o-mini" }
          ]
        }.to_json
      }
    end

    result = fetcher.call

    assert result.ok
    assert_equal [["https://api.openai.com/v1/models", "Bearer sk-test"]], requested
    assert_equal %w[gpt-4o gpt-4o-mini], result.models
  end

  test "reports missing openai api key" do
    connection = service_connections(:openai)
    connection.update!(api_token: nil)

    result = ServiceConnectionModelFetcher.new(connection).call

    assert_not result.ok
    assert_match(/API キー/, result.message)
  end

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

  test "fetches models for custom llm" do
    connection = ServiceConnection.create!(
      key: "llm_fetch_test",
      name: "Fetch Test",
      base_url: "http://balvenie:10012",
      server_model: "test-model"
    )
    fetcher = ServiceConnectionModelFetcher.new(connection)
    fetcher.define_singleton_method(:perform_get) do |uri, **|
      { status: 200, body: { data: [{ id: "custom-model" }] }.to_json }
    end

    result = fetcher.call

    assert result.ok
    assert_equal ["custom-model"], result.models
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
