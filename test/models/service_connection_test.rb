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

  test "chat_keys includes custom llms" do
    ServiceConnection.create!(
      key: "llm_extra",
      name: "Extra",
      base_url: "http://example.com:8080",
      server_model: "extra-model"
    )

    assert_includes ServiceConnection.chat_keys, "llm_extra"
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
end
