# frozen_string_literal: true

require "test_helper"

class MemoRagStatusTest < ActiveSupport::TestCase
  test "reports memo chunk counts" do
    PromptKnowledgeChunk.create!(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: "kbmemo:01J8X2K3M4N5P6Q7R8S9T0UVWX:chunk:0",
      title: "旅行",
      body: "京都",
      metadata: {
        memo_uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX",
        memo_updated_at: "2026-07-01T12:00:00Z"
      },
      skip_auto_embed: true,
      embedding: EmbeddingClient.new.embed(input: "京都")
    )

    stats = MemoRagStatus.current

    assert_equal 1, stats.chunk_count
    assert_equal 1, stats.memo_count
    assert stats.last_synced_at.present?
  end
end
