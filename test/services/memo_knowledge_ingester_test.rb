# frozen_string_literal: true

require "test_helper"

class MemoKnowledgeIngesterTest < ActiveSupport::TestCase
  test "creates memo chunks with embeddings" do
    memo = {
      "id" => 42,
      "uid" => "01J8X2K3M4N5P6Q7R8S9T0UVWX",
      "title" => "旅行メモ",
      "body" => "京都に行った。\n\n清水寺が良かった。",
      "updated_at" => "2026-07-01T12:00:00Z"
    }

    count = MemoKnowledgeIngester.new(chunker: MemoTextChunker.new(max_chars: 500)).ingest!(memo)

    assert_equal 2, count
    chunks = PromptKnowledgeChunk.from_memo.order(:id)
    assert_equal 2, chunks.size
    assert_equal "kbmemo:01J8X2K3M4N5P6Q7R8S9T0UVWX:chunk:0", chunks.first.external_id
    assert chunks.all? { |chunk| chunk.embedding.present? }
    assert_equal "01J8X2K3M4N5P6Q7R8S9T0UVWX", chunks.first.metadata["memo_uid"]
  end

  test "replaces existing chunks for the same memo uid" do
    memo = {
      "id" => 7,
      "uid" => "01J8X2K3M4N5P6Q7R8S9T0UVWY",
      "title" => "更新前",
      "body" => "旧本文",
      "updated_at" => "2026-07-01T12:00:00Z"
    }
    ingester = MemoKnowledgeIngester.new

    ingester.ingest!(memo)
    memo["body"] = "新しい本文だけ"
    ingester.ingest!(memo)

    chunks = PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", memo["uid"])
    assert_equal 1, chunks.count
    assert_includes chunks.first.body, "新しい本文"
  end
end
