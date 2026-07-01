# frozen_string_literal: true

require "test_helper"

class ServiceConnectionTest < ActiveSupport::TestCase
  test "builtin connection cannot be destroyed" do
    connection = service_connections(:llama_cpp)

    assert_not connection.destroy
    assert_includes connection.errors[:base], "組み込み接続は削除できません。無効化してください。"
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
