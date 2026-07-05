# frozen_string_literal: true

require "test_helper"

class ChatTools::ToolResponseTest < ActiveSupport::TestCase
  test "preview returns json string" do
    payload = ChatTools::ToolResponse.preview(ok: true, tool: "fetch_url", content_preview: "hello")

    parsed = JSON.parse(payload)
    assert_equal true, parsed["ok"]
    assert_equal "hello", parsed["content_preview"]
  end

  test "limit_reached returns structured plain text" do
    message = ChatTools::ToolResponse.limit_reached(
      tool: "fetch_url",
      code: "FETCH_LIMIT_EXCEEDED",
      message: "上限です"
    )

    assert_includes message, ChatTools::ToolResponse::LIMIT_PREFIX
    assert_includes message, "CODE: FETCH_LIMIT_EXCEEDED"
    assert_includes message, "RETRYABLE: false"
    assert_includes message, "EXHAUSTED: true"
    assert_includes message, "fetch_url を再実行してはいけません"
  end

  test "error returns structured plain text" do
    message = ChatTools::ToolResponse.error(
      tool: "fetch_url",
      code: "DUPLICATE_URL",
      retryable: false,
      url: "https://example.com",
      message: "既に取得済み"
    )

    assert_includes message, ChatTools::ToolResponse::ERROR_PREFIX
    assert_includes message, "CODE: DUPLICATE_URL"
    assert_includes message, "RETRYABLE: false"
    assert_includes message, "URL: https://example.com"
    assert_includes message, "既に取得済み"
  end
end
