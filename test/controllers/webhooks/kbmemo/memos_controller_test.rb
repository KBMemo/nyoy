# frozen_string_literal: true

require "test_helper"

class Webhooks::Kbmemo::MemosControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_enabled = Rails.application.config.x.nyoy.memo_rag_webhook_enabled
    @original_secret = Rails.application.config.x.nyoy.memo_rag_webhook_secret
    Rails.application.config.x.nyoy.memo_rag_webhook_enabled = true
    Rails.application.config.x.nyoy.memo_rag_webhook_secret = "test-secret"
  end

  teardown do
    Rails.application.config.x.nyoy.memo_rag_webhook_enabled = @original_enabled
    Rails.application.config.x.nyoy.memo_rag_webhook_secret = @original_secret
  end

  test "returns not found when webhook is disabled" do
    Rails.application.config.x.nyoy.memo_rag_webhook_enabled = false

    post webhooks_kbmemo_memos_path, params: signed_body(payload).fetch(:body), headers: signed_body(payload).fetch(:headers)

    assert_response :not_found
  end

  test "accepts signed event and enqueues processing job" do
    signed = signed_body(payload)

    assert_enqueued_with(job: MemoKnowledgeWebhookJob, args: [ payload.fetch(:event_id) ]) do
      post webhooks_kbmemo_memos_path, params: signed.fetch(:body), headers: signed.fetch(:headers)
    end

    assert_response :accepted
    body = JSON.parse(response.body)
    assert_equal true, body["accepted"]
    assert_equal payload.fetch(:event_id), body["event_id"]

    event = MemoRagWebhookEvent.find_by!(event_id: payload.fetch(:event_id))
    assert_equal "memo.updated", event.event_type
    assert_equal "pending", event.status
  end

  test "duplicate event is accepted without enqueueing another job" do
    MemoRagWebhookEvent.create!(
      event_id: payload.fetch(:event_id),
      event_type: "memo.updated",
      account_id: 1,
      memo_uid: payload.fetch(:memo_uid),
      occurred_at: Time.current
    )
    signed = signed_body(payload)

    assert_no_enqueued_jobs do
      post webhooks_kbmemo_memos_path, params: signed.fetch(:body), headers: signed.fetch(:headers)
    end

    assert_response :success
    assert_equal true, JSON.parse(response.body)["duplicate"]
  end

  test "rejects invalid signature" do
    signed = signed_body(payload)
    headers = signed.fetch(:headers).merge("X-KBMemo-Signature" => "sha256=bad")

    post webhooks_kbmemo_memos_path, params: signed.fetch(:body), headers: headers

    assert_response :unauthorized
  end

  test "returns validation error for missing required field" do
    signed = signed_body(payload.except(:memo_uid))

    post webhooks_kbmemo_memos_path, params: signed.fetch(:body), headers: signed.fetch(:headers)

    assert_response :unprocessable_entity
    assert_equal "validation_error", JSON.parse(response.body).dig("error", "code")
  end

  private

  def payload
    {
      event_id: "01KXQWEBHOOK0000000000001",
      event_type: "memo.updated",
      account_id: 1,
      memo_uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX",
      memo_id: 42,
      occurred_at: Time.current.utc.iso8601,
      memo_updated_at: Time.current.utc.iso8601
    }
  end

  def signed_body(payload)
    body = JSON.generate(payload)
    timestamp = Time.current.utc.iso8601
    digest = OpenSSL::HMAC.hexdigest("sha256", "test-secret", "#{timestamp}.#{body}")
    {
      body: body,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "X-KBMemo-Webhook-Timestamp" => timestamp,
        "X-KBMemo-Signature" => "sha256=#{digest}"
      }
    }
  end
end
