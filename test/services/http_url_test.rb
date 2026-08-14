# frozen_string_literal: true

require "test_helper"

class HttpUrlTest < ActiveSupport::TestCase
  TOTO_URL = "https://store.toto-dream.com/dcs/subos/screen/pi01/spin000/PGSPIN00001DisptotoLotInfo.form?holdCntId=1645"
  TOTO_CORRUPTED = "https://store.toto-dream.com/dcs subos/screen/pi01/spin 000/PG SPIN00001 Disptoto LotInfo.form? holdCntId=1645"

  test "normalize leaves a valid ascii url unchanged" do
    assert_equal "https://example.com/path?q=1", HttpUrl.normalize("https://example.com/path?q=1")
  end

  test "normalize percent-encodes japanese paths" do
    uri = HttpUrl.parse("https://ja.wikipedia.org/wiki/元三大師")

    assert_equal "/wiki/%E5%85%83%E4%B8%89%E5%A4%A7%E5%B8%AB", uri.path
  end

  test "repairs llm tool-call spaces in a toto lottery url" do
    assert_equal TOTO_URL, HttpUrl.normalize(TOTO_CORRUPTED)
    assert_equal TOTO_URL, HttpUrl.parse(TOTO_CORRUPTED).to_s
  end

  test "repairs a slash that the model replaced with a space" do
    assert_equal "https://example.com/dcs/subos/page",
                 HttpUrl.normalize("https://example.com/dcs subos/page")
  end

  test "encodes leftover query spaces instead of turning them into slashes" do
    assert_equal "https://example.com/search?q=hello%20world",
                 HttpUrl.normalize("https://example.com/search?q=hello world")
  end

  test "extract_all keeps explicit urls from a user message" do
    text = "このページを見て #{TOTO_URL} 要約して"

    assert_equal [ TOTO_URL ], HttpUrl.extract_all(text)
  end

  test "recover_from_explicit restores a spaced tool url from the user message" do
    recovered = HttpUrl.recover_from_explicit(TOTO_CORRUPTED, [ TOTO_URL ])

    assert_equal TOTO_URL, recovered
  end

  test "recover_from_explicit ignores a valid unrelated url" do
    assert_nil HttpUrl.recover_from_explicit("https://example.com/other", [ TOTO_URL ])
  end
end
