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

  test "delete_memo removes chunks for the memo uid" do
    uid = "01J8X2K3M4N5P6Q7R8S9T0UVWZ"
    chunk = PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: PromptKnowledgeChunk.memo_external_id(uid, 0),
      title: "削除対象",
      body: "本文",
      metadata: { memo_uid: uid }
    )
    chunk.skip_auto_embed = true
    chunk.save!

    deleted_count = MemoKnowledgeIngester.new.delete_memo!(uid)

    assert_equal 1, deleted_count
    assert_not PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", uid).exists?
  end

  test "delete_except_memos removes stale memo chunks" do
    keep_uid = "01J8X2K3M4N5P6Q7R8S9T0UVA1"
    stale_uid = "01J8X2K3M4N5P6Q7R8S9T0UVA2"
    [ keep_uid, stale_uid ].each do |uid|
      chunk = PromptKnowledgeChunk.new(
        source: PromptKnowledgeChunk::SOURCE_MEMO,
        kind: "memo",
        external_id: PromptKnowledgeChunk.memo_external_id(uid, 0),
        title: uid,
        body: "本文",
        metadata: { memo_uid: uid }
      )
      chunk.skip_auto_embed = true
      chunk.save!
    end

    deleted_count = MemoKnowledgeIngester.new.delete_except_memos!([ keep_uid ])

    assert_equal 1, deleted_count
    assert PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", keep_uid).exists?
    assert_not PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", stale_uid).exists?
  end

  test "stale_memo_update detects older webhook timestamps" do
    uid = "01J8X2K3M4N5P6Q7R8S9T0UVA3"
    chunk = PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: PromptKnowledgeChunk.memo_external_id(uid, 0),
      title: uid,
      body: "本文",
      metadata: { memo_uid: uid, memo_updated_at: "2026-07-02T00:00:00Z" }
    )
    chunk.skip_auto_embed = true
    chunk.save!

    ingester = MemoKnowledgeIngester.new

    assert ingester.stale_memo_update?(uid, "2026-07-01T00:00:00Z")
    assert ingester.stale_memo_update?(uid, "2026-07-02T00:00:00Z")
    assert_not ingester.stale_memo_update?(uid, "2026-07-03T00:00:00Z")
  end
end
