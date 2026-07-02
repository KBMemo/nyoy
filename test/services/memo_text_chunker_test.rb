# frozen_string_literal: true

require "test_helper"

class MemoTextChunkerTest < ActiveSupport::TestCase
  test "splits on blank lines and headings" do
    body = "== 見出し\n\n第一段。\n\n第二段。"
    chunks = MemoTextChunker.new(max_chars: 1500).chunk(body)

    assert_equal 3, chunks.size
    assert_includes chunks.first, "見出し"
    assert_equal "第二段。", chunks.last
  end

  test "splits oversized sections" do
    body = "a" * 2500
    chunks = MemoTextChunker.new(max_chars: 1000).chunk(body)

    assert chunks.size >= 2
    assert chunks.all? { |chunk| chunk.length <= 1000 }
  end
end
