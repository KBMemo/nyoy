# frozen_string_literal: true

require "test_helper"

class ServiceConnectionProbeTest < ActiveSupport::TestCase
  test "succeeds via health endpoint for llama connection" do
    connection = service_connections(:llama_cpp)
    probe = ServiceConnectionProbe.new(connection)
    requested = []
    probe.define_singleton_method(:perform_get) do |uri, **|
      requested << uri.to_s
      { status: 200, body: "ok" }
    end

    result = probe.call

    assert result.ok
    assert_equal "http://balvenie:10010/health", requested.first
    assert_match(/接続できました/, result.message)
    assert_operator result.latency_ms, :>=, 0
  end

  test "falls back to models endpoint when health is unavailable" do
    connection = service_connections(:embeddings)
    probe = ServiceConnectionProbe.new(connection)
    calls = []
    probe.define_singleton_method(:perform_get) do |uri, **|
      calls << uri.path
      if uri.path == "/health"
        { status: 404, body: "not found" }
      else
        { status: 200, body: { data: [{ id: "groonga/bge-m3-Q4_K_M-GGUF" }] }.to_json }
      end
    end

    result = probe.call

    assert result.ok
    assert_includes calls, "/v1/models"
    assert_match(/モデル 1 件/, result.message)
  end

  test "reports sd switchd token missing" do
    connection = service_connections(:sd_switchd)
    connection.update!(api_token: nil)
    result = nil

    NyoyConnectionStore.singleton_class.alias_method(:__probe_test_api_token, :api_token)
    NyoyConnectionStore.define_singleton_method(:api_token) { |_key| nil }
    begin
      result = ServiceConnectionProbe.new(connection).call
    ensure
      if NyoyConnectionStore.singleton_class.method_defined?(:__probe_test_api_token, false)
        NyoyConnectionStore.singleton_class.alias_method(:api_token, :__probe_test_api_token)
        NyoyConnectionStore.singleton_class.remove_method(:__probe_test_api_token)
      end
    end

    assert_not result.ok
    assert_match(/トークン/, result.message)
  end

  test "reports connection errors" do
    connection = service_connections(:sd_cpp)
    probe = ServiceConnectionProbe.new(connection)
    probe.define_singleton_method(:perform_get) do |*, **|
      raise ServiceConnectionProbe::Error, "接続できませんでした（Failed to open TCP connection）"
    end

    result = probe.call

    assert_not result.ok
    assert_match(/接続できません/, result.message)
  end
end
