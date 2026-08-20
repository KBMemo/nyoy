# frozen_string_literal: true

require "test_helper"

class ChatTools::ToolResponseTest < ActiveSupport::TestCase
  test "preview returns json string" do
    payload = ChatTools::ToolResponse.preview(ok: true, tool: "fetch_url", content_preview: "hello")

    parsed = JSON.parse(payload)
    assert_equal true, parsed["ok"]
    assert_equal "hello", parsed["content_preview"]
  end

  test "preview accepts binary-tagged utf-8 cut mid character" do
    # Mimics Net::HTTP / readability body: valid UTF-8 bytes as ASCII-8BIT,
    # truncated mid multibyte sequence (ア = E3 82 A2).
    broken = "アジサイ".b.byteslice(0, 5)

    payload = ChatTools::ToolResponse.preview(
      ok: true,
      tool: "fetch_url",
      title: "凛".b,
      content_preview: broken
    )

    parsed = JSON.parse(payload)
    assert_equal Encoding::UTF_8, parsed["content_preview"].encoding
    assert parsed["content_preview"].valid_encoding?
    assert_equal "凛", parsed["title"]
  end

  test "truncate_chars keeps valid utf-8 when limiting length" do
    text = "第1647回 toto 岡山 vs FC東京"

    truncated = ChatTools::ToolResponse.truncate_chars(text, 10)

    assert truncated.valid_encoding?
    assert_equal 10, truncated.length
  end

  test "preview serializes recall_memos context with broken utf-8" do
    broken = "toto ".b + "岡山".b.byteslice(0, 2)

    payload = ChatTools::ToolResponse.preview(context: broken)

    parsed = JSON.parse(payload)
    assert parsed["context"].valid_encoding?
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
