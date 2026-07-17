# frozen_string_literal: true

require "test_helper"

class MemoRagWebhookStatusTest < ActiveSupport::TestCase
  setup do
    @original_enabled = Rails.application.config.x.nyoy.memo_rag_webhook_enabled
    @original_secret = Rails.application.config.x.nyoy.memo_rag_webhook_secret
    Rails.application.config.x.nyoy.memo_rag_webhook_enabled = true
    Rails.application.config.x.nyoy.memo_rag_webhook_secret = "secret"
  end

  teardown do
    Rails.application.config.x.nyoy.memo_rag_webhook_enabled = @original_enabled
    Rails.application.config.x.nyoy.memo_rag_webhook_secret = @original_secret
  end

  test "reports webhook configuration and event counts" do
    completed = create_event!("memo.updated", status: "completed", processed_at: 1.minute.ago)
    failed = create_event!("memo.deleted", status: "failed", error_message: "boom")

    stats = MemoRagWebhookStatus.current

    assert stats.enabled
    assert stats.secret_configured
    assert_equal 2, stats.total_events
    assert_equal 1, stats.status_counts.fetch("completed")
    assert_equal 1, stats.status_counts.fetch("failed")
    assert_includes stats.recent_events.map(&:event_id), completed.event_id
    assert_equal [failed.event_id], stats.failed_events.map(&:event_id)
    assert stats.last_received_at.present?
    assert stats.last_processed_at.present?
  end

  test "reports stuck pending and processing events" do
    old_pending = create_event!("memo.updated", status: "pending", updated_at: 20.minutes.ago)
    create_event!("memo.updated", status: "pending", updated_at: 1.minute.ago)
    create_event!("memo.updated", status: "completed", updated_at: 20.minutes.ago, processed_at: 19.minutes.ago)

    stats = MemoRagWebhookStatus.current

    assert_equal [old_pending.event_id], stats.stuck_events.map(&:event_id)
  end

  private

  def create_event!(event_type, status:, error_message: nil, processed_at: nil, updated_at: nil)
    event = MemoRagWebhookEvent.create!(
      event_id: "event-#{SecureRandom.hex(4)}",
      event_type: event_type,
      account_id: 1,
      memo_uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX",
      occurred_at: Time.current,
      status: status,
      error_message: error_message,
      processed_at: processed_at
    )
    event.update_columns(updated_at: updated_at) if updated_at
    event
  end
end
