# frozen_string_literal: true

require "test_helper"

class MemoKnowledgeRetrieverTest < ActiveSupport::TestCase
  setup do
    @uid = "01J8X2K3M4N5P6Q7R8S9T0UVWZ"
    create_memo_chunk!(
      title: "京都旅行",
      body: "清水寺と伏見稲荷へ行った",
      uid: @uid,
      index: 0
    )
    create_memo_chunk!(
      title: "開発メモ",
      body: "Rails と pgvector の設定",
      uid: "01J8X2K3M4N5P6Q7R8S9T0UVW0",
      index: 0
    )
  end

  test "returns memo chunks for vector query" do
    results = MemoKnowledgeRetriever.new(limit: 1).retrieve("京都 清水寺")

    assert_equal 1, results.size
    assert_equal "memo", results.first.kind
    assert_includes results.first.body, "清水寺"
  end

  test "uses higher top_k for complex queries" do
    analysis = MemoRagQueryAnalyzer.analyze("比較してまとめて")
    assert_equal 10, analysis.top_k

    results = MemoKnowledgeRetriever.new(limit: analysis.top_k).retrieve("比較してまとめて")
    assert results.size <= 10
  end

  test "merges keyword hits from tsurezure client" do
    client = TsurezureClient.new(base_url: "https://kbmemo.example.com", api_token: "kbmemo_test")
    client.define_singleton_method(:configured?) { true }
    client.define_singleton_method(:list_memos) do |**|
      { "memos" => [{ "uid" => @uid, "title" => "京都旅行" }] }
    end

    results = MemoKnowledgeRetriever.new(tsurezure_client: client, limit: 2).retrieve("京都")

    assert results.any? { |chunk| chunk.metadata["memo_uid"] == @uid }
  end

  private

  def create_memo_chunk!(title:, body:, uid:, index:)
    chunk = PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: PromptKnowledgeChunk.memo_external_id(uid, index),
      title: title,
      body: body,
      metadata: {
        memo_uid: uid,
        chunk_index: index,
        chunk_count: 1,
        memo_updated_at: "2026-07-01T12:00:00Z"
      }
    )
    chunk.skip_auto_embed = true
    chunk.embedding = EmbeddingClient.new.embed(input: "#{title}\n\n#{body}")
    chunk.save!
    chunk
  end
end
