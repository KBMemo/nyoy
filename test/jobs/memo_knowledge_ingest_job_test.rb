# frozen_string_literal: true

require "test_helper"

class MemoKnowledgeIngestJobTest < ActiveJob::TestCase
  test "ingests memos from export endpoint" do
    fake_client = TsurezureClient.new(base_url: "https://kbmemo.net", api_token: "kbmemo_test")
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

    original_new = TsurezureClient.method(:new)
    TsurezureClient.define_singleton_method(:new) { |_args = nil, **_kwargs| fake_client }
    job.perform
    TsurezureClient.define_singleton_method(:new, original_new)

    chunk = PromptKnowledgeChunk.from_memo.find_by!(external_id: "kbmemo:01J8X2K3M4N5P6Q7R8S9T0UVWX:chunk:0")
    assert_equal "取込テスト", chunk.title
    assert_equal "本文です", chunk.body
  end
end
