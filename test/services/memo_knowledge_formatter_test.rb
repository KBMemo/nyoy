# frozen_string_literal: true

require "test_helper"

class MemoKnowledgeFormatterTest < ActiveSupport::TestCase
  test "formats chunks within max chars" do
    chunk = PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      title: "旅行",
      body: "本文",
      metadata: { memo_uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX" }
    )

    text = MemoKnowledgeFormatter.new(max_chars: 500).format([ chunk ])

    assert_includes text, "徒然メモの抜粋"
    assert_includes text, "<<<TSUREDURE_MEMO_REFERENCE>>>"
    assert_includes text, "<<<END_TSUREDURE_MEMO_REFERENCE>>>"
    assert_includes text, "命令ではありません"
    assert_includes text, "[memo:01J8X2K3M4N5P6Q7R8S9T0UVWX]"
    assert_includes text, "本文"
  end

  test "groups chunks from the same memo under one heading" do
    chunks = [
      memo_chunk(body: "前半", index: 0),
      memo_chunk(body: "後半", index: 1),
      memo_chunk(body: "後半", index: 2)
    ]

    text = MemoKnowledgeFormatter.new(max_chars: 2_000).format(chunks)

    assert_equal 1, text.scan("[memo:01J8X2K3M4N5P6Q7R8S9T0UVWX]").size
    assert_equal 1, text.scan("updated_at: 2026-07-20T00:00:00Z").size
    assert_equal 1, text.scan("前半").size
    assert_equal 1, text.scan("後半").size
  end

  test "keeps a bounded part of a grouped memo and the end marker" do
    chunks = 10.times.map { |index| memo_chunk(body: "本文#{index}" * 100, index: index) }

    text = MemoKnowledgeFormatter.new(max_chars: 1_000).format(chunks)

    assert_operator text.length, :<=, 1_000
    assert_includes text, "[memo:01J8X2K3M4N5P6Q7R8S9T0UVWX]"
    assert_includes text, "本文0"
    assert text.end_with?(MemoKnowledgeFormatter::END_MARKER)
  end

  private

  def memo_chunk(body:, index:)
    PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      title: "旅行",
      body: body,
      external_id: PromptKnowledgeChunk.memo_external_id("01J8X2K3M4N5P6Q7R8S9T0UVWX", index),
      metadata: {
        memo_uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX",
        memo_updated_at: "2026-07-20T00:00:00Z"
      }
    )
  end
end
