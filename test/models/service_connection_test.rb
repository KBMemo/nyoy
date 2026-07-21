# frozen_string_literal: true

require "test_helper"

class ServiceConnectionTest < ActiveSupport::TestCase
  test "builtin connection cannot be destroyed" do
    connection = service_connections(:llama_cpp)

    assert_not connection.destroy
    assert_includes connection.errors[:base], "組み込み接続は削除できません。無効化してください。"
  end

  test "custom llm requires llm_ prefix and server_model" do
    connection = ServiceConnection.new(
      key: "not_llm",
      name: "Bad",
      base_url: "http://example.com:8080"
    )

    assert_not connection.valid?
    assert_includes connection.errors[:key], "は組み込み key か llm_ で始まるカスタム key にしてください"

    connection.key = "llm_test_server"
    assert_not connection.valid?
    assert connection.errors[:server_model].any?

    connection.server_model = "test-model"
    assert connection.valid?
  end

  test "custom llm can be destroyed" do
    connection = ServiceConnection.create!(
      key: "llm_test_destroy",
      name: "Test LLM",
      base_url: "http://example.com:8080",
      server_model: "test-model"
    )

    assert connection.destroy
    assert_not ServiceConnection.exists?(connection.id)
  end

  test "model endpoints include custom llms by adapter" do
    ServiceConnection.create!(
      key: "llm_extra",
      name: "Extra",
      base_url: "http://example.com:8080",
      adapter: "llama_cpp",
      server_model: "extra-model"
    )

    assert_includes ServiceConnection.model_endpoints.pluck(:key), "llama_server_extra_model"
    assert_equal ServiceConnection.resolve("llm_extra"), ServiceConnection.find_by!(key: "llama_server_extra_model")
  end

  test "custom llm defaults to llama cpp adapter" do
    connection = ServiceConnection.new(
      key: "llm_adapter_default",
      name: "Adapter default",
      base_url: "http://example.com:8080",
      server_model: "test-model"
    )

    assert connection.valid?
    assert_equal "llama_cpp", connection.adapter
    assert_equal "llama_server_test_model", connection.key
    assert_equal "llm_adapter_default", connection.legacy_key
  end

  test "validates base_url format" do
    connection = ServiceConnection.new(
      key: "llama_cpp",
      name: "bad",
      base_url: "not-a-url"
    )

    assert_not connection.valid?
    assert_includes connection.errors[:base_url], "は http:// または https:// で始めてください"
  end

  test "enabled OpenAI connection accepts an environment API token" do
    original = Rails.application.config.x.nyoy.openai_api_key
    Rails.application.config.x.nyoy.openai_api_key = "sk-env"
    connection = service_connections(:openai)
    connection.assign_attributes(enabled: true, api_token: nil)

    assert connection.valid?
    assert_equal "environment", connection.api_token_source
    assert connection.api_token_configured?
  ensure
    Rails.application.config.x.nyoy.openai_api_key = original
  end

  test "enabled OpenAI connection still requires a token without environment fallback" do
    original = Rails.application.config.x.nyoy.openai_api_key
    Rails.application.config.x.nyoy.openai_api_key = nil
    connection = service_connections(:openai)
    connection.assign_attributes(enabled: true, api_token: nil)

    assert_not connection.valid?
    assert connection.errors[:api_token].any?
  ensure
    Rails.application.config.x.nyoy.openai_api_key = original
  end

  test "stores a valid llama switchd public host" do
    connection = service_connections(:llama_switchd)

    connection.assign_llama_switchd_settings(public_host: "llm-data.example.net")

    assert connection.valid?
    assert_equal "llm-data.example.net", connection.llama_switchd_settings.public_host
  end

  test "rejects a llama switchd public host containing a port or path" do
    connection = service_connections(:llama_switchd)

    [ "llm-data.example.net:80", "llm-data.example.net:10010", "llm-data.example.net/path" ].each do |public_host|
      connection.assign_llama_switchd_settings(public_host: public_host)

      assert_not connection.valid?
      assert connection.errors[:settings].any?
    end
  end
end
