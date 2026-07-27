# frozen_string_literal: true

require "test_helper"

class MemoKnowledgeIngestJobTest < ActiveJob::TestCase
  test "ingests memos from export endpoint" do
    stale_uid = "01J8X2K3M4N5P6Q7R8S9T0UVWA"
    stale_chunk = PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: PromptKnowledgeChunk.memo_external_id(stale_uid, 0),
      title: "削除済み",
      body: "古い本文",
      metadata: { memo_uid: stale_uid }
    )
    stale_chunk.skip_auto_embed = true
    stale_chunk.save!

    fake_client = TsurezureClient.new(base_url: "https://kbmemo.example.com", api_token: "kbmemo_test")
    fake_client.define_singleton_method(:export_memos) do |**|
      {
        "memos" => [
          {
            "id" => 1,
            "uid" => "01J8X2K3M4N5P6Q7R8S9T0UVWX",
            "title" => "取込テスト",
            "body" => "本文です",
            "updated_at" => "2026-07-01T12:00:00Z"
          }
        ],
        "pagination" => { "has_more" => false }
      }
    end

    job = MemoKnowledgeIngestJob.new
    job.define_singleton_method(:ingest_enabled?) { true }

    with_tsurezure_client(fake_client) { job.perform }

    chunk = PromptKnowledgeChunk.from_memo.find_by!(external_id: "kbmemo:01J8X2K3M4N5P6Q7R8S9T0UVWX:chunk:0")
    assert_equal "取込テスト", chunk.title
    assert_equal "本文です", chunk.body
    assert_not PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", stale_uid).exists?
    assert AppSetting.memo_knowledge_last_ingested_at.present?
  end

  test "syncs memo deletions from export deletions endpoint using stored checkpoint" do
    deleted_uid = "01J8X2K3M4N5P6Q7R8S9T0UVWY"
    checkpoint = Time.utc(2026, 7, 1, 0, 0, 0)
    AppSetting.update_memo_knowledge_last_ingested_at!(checkpoint)
    chunk = PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: PromptKnowledgeChunk.memo_external_id(deleted_uid, 0),
      title: "削除対象",
      body: "本文",
      metadata: { memo_uid: deleted_uid }
    )
    chunk.skip_auto_embed = true
    chunk.save!

    fake_client = TsurezureClient.new(base_url: "https://kbmemo.example.com", api_token: "kbmemo_test")
    export_calls = []
    fake_client.define_singleton_method(:export_memos) do |updated_since: nil, **|
      export_calls << updated_since
      {
        "memos" => [],
        "pagination" => { "has_more" => false }
      }
    end
    deletion_calls = []
    fake_client.define_singleton_method(:export_memo_deletions) do |deleted_since:, **|
      deletion_calls << deleted_since
      {
        "deletions" => [
          { "uid" => deleted_uid, "deleted_at" => "2026-07-01T12:00:00Z" }
        ],
        "pagination" => { "has_more" => false }
      }
    end

    job = MemoKnowledgeIngestJob.new
    job.define_singleton_method(:ingest_enabled?) { true }

    with_tsurezure_client(fake_client) { job.perform }

    assert_equal [ checkpoint ], export_calls
    assert_equal [ checkpoint ], deletion_calls
    assert_not PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", deleted_uid).exists?
    assert AppSetting.memo_knowledge_last_ingested_at > checkpoint
  end

  private

  def with_tsurezure_client(client)
    original_new = TsurezureClient.method(:new)
    TsurezureClient.define_singleton_method(:new) { |_args = nil, **_kwargs| client }
    yield
  ensure
    TsurezureClient.define_singleton_method(:new, original_new)
  end
end
