# frozen_string_literal: true

require "test_helper"

class MemoKnowledgeWebhookJobTest < ActiveJob::TestCase
  test "deleted event removes memo chunks" do
    uid = "01J8X2K3M4N5P6Q7R8S9T0UVWB"
    create_memo_chunk!(uid: uid)
    event = create_event!(event_type: "memo.deleted", memo_uid: uid)

    MemoKnowledgeWebhookJob.perform_now(event.event_id)

    assert_not PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", uid).exists?
    assert_equal "completed", event.reload.status
    assert event.processed_at.present?
  end

  test "updated event fetches memo and ingests chunks" do
    uid = "01J8X2K3M4N5P6Q7R8S9T0UVWC"
    event = create_event!(event_type: "memo.updated", memo_uid: uid, memo_updated_at: Time.utc(2026, 7, 1, 0, 0, 0))
    fake_client = fake_client_for(uid => {
      "id" => 42,
      "uid" => uid,
      "title" => "Webhook memo",
      "body" => "Webhook body",
      "updated_at" => "2026-07-01T00:00:00Z",
      "draft" => false
    })

    with_tsurezure_client(fake_client) { MemoKnowledgeWebhookJob.perform_now(event.event_id) }

    chunk = PromptKnowledgeChunk.from_memo.find_by!("metadata->>'memo_uid' = ?", uid)
    assert_equal "Webhook memo", chunk.title
    assert_equal "Webhook body", chunk.body
    assert_equal "completed", event.reload.status
  end

  test "updated event deletes chunks and skips when memo is draft" do
    uid = "01J8X2K3M4N5P6Q7R8S9T0UVWD"
    create_memo_chunk!(uid: uid)
    event = create_event!(event_type: "memo.updated", memo_uid: uid)
    fake_client = fake_client_for(uid => {
      "id" => 42,
      "uid" => uid,
      "title" => "Draft memo",
      "body" => "Draft body",
      "updated_at" => "2026-07-01T00:00:00Z",
      "draft" => true
    })

    with_tsurezure_client(fake_client) { MemoKnowledgeWebhookJob.perform_now(event.event_id) }

    assert_not PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", uid).exists?
    assert_equal "skipped", event.reload.status
    assert_equal "memo is draft", event.error_message
  end

  test "updated event deletes chunks and skips when memo is not visible" do
    uid = "01J8X2K3M4N5P6Q7R8S9T0UVWE"
    create_memo_chunk!(uid: uid)
    event = create_event!(event_type: "memo.updated", memo_uid: uid)
    fake_client = TsurezureClient.new(base_url: "https://kbmemo.net", api_token: "kbmemo_test")
    fake_client.define_singleton_method(:get_memo) do |_memo_ref, **|
      raise TsurezureClient::Error.new("not found", status: 404)
    end

    with_tsurezure_client(fake_client) { MemoKnowledgeWebhookJob.perform_now(event.event_id) }

    assert_not PromptKnowledgeChunk.from_memo.where("metadata->>'memo_uid' = ?", uid).exists?
    assert_equal "skipped", event.reload.status
    assert_equal "memo is not visible via kbmemo API", event.error_message
  end

  test "stale updated event is skipped" do
    uid = "01J8X2K3M4N5P6Q7R8S9T0UVWF"
    create_memo_chunk!(uid: uid, memo_updated_at: "2026-07-02T00:00:00Z")
    event = create_event!(
      event_type: "memo.updated",
      memo_uid: uid,
      memo_updated_at: Time.utc(2026, 7, 1, 0, 0, 0)
    )
    fake_client = fake_client_for(uid => {
      "id" => 42,
      "uid" => uid,
      "title" => "Older memo",
      "body" => "Older body",
      "updated_at" => "2026-07-01T00:00:00Z",
      "draft" => false
    })

    with_tsurezure_client(fake_client) { MemoKnowledgeWebhookJob.perform_now(event.event_id) }

    assert_equal "skipped", event.reload.status
    assert_equal "stale memo update", event.error_message
    assert_equal "Existing body", PromptKnowledgeChunk.from_memo.find_by!("metadata->>'memo_uid' = ?", uid).body
  end

  private

  def create_event!(event_type:, memo_uid:, memo_updated_at: nil)
    MemoRagWebhookEvent.create!(
      event_id: "event-#{memo_uid}",
      event_type: event_type,
      account_id: 1,
      memo_uid: memo_uid,
      memo_id: 42,
      memo_updated_at: memo_updated_at,
      occurred_at: Time.current
    )
  end

  def create_memo_chunk!(uid:, memo_updated_at: "2026-07-01T00:00:00Z")
    chunk = PromptKnowledgeChunk.new(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: PromptKnowledgeChunk.memo_external_id(uid, 0),
      title: "Existing memo",
      body: "Existing body",
      metadata: { memo_uid: uid, memo_updated_at: memo_updated_at }
    )
    chunk.skip_auto_embed = true
    chunk.save!
    chunk
  end

  def fake_client_for(memos)
    client = TsurezureClient.new(base_url: "https://kbmemo.net", api_token: "kbmemo_test")
    client.define_singleton_method(:get_memo) do |memo_ref, **|
      memos.fetch(memo_ref)
    end
    client
  end

  def with_tsurezure_client(client)
    original_new = TsurezureClient.method(:new)
    TsurezureClient.define_singleton_method(:new) { |_args = nil, **_kwargs| client }
    yield
  ensure
    TsurezureClient.define_singleton_method(:new, original_new)
  end
end
