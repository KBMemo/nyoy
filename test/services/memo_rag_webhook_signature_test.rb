# frozen_string_literal: true

require "test_helper"

class MemoRagWebhookSignatureTest < ActiveSupport::TestCase
  test "verifies valid hmac signature" do
    raw_body = { event_id: "01EVENT" }.to_json
    timestamp = Time.current.utc.iso8601
    secret = "test-secret"
    signature = signature_for(raw_body, timestamp, secret)

    assert MemoRagWebhookSignature.verify!(
      raw_body: raw_body,
      timestamp: timestamp,
      signature: signature,
      secret: secret
    )
  end

  test "rejects invalid hmac signature" do
    error = assert_raises(MemoRagWebhookSignature::Error) do
      MemoRagWebhookSignature.verify!(
        raw_body: "{}",
        timestamp: Time.current.utc.iso8601,
        signature: "sha256=bad",
        secret: "test-secret"
      )
    end

    assert_equal "webhook signature is invalid", error.message
  end

  test "rejects stale timestamp" do
    raw_body = "{}"
    timestamp = 10.minutes.ago.utc.iso8601
    secret = "test-secret"

    error = assert_raises(MemoRagWebhookSignature::Error) do
      MemoRagWebhookSignature.verify!(
        raw_body: raw_body,
        timestamp: timestamp,
        signature: signature_for(raw_body, timestamp, secret),
        secret: secret
      )
    end

    assert_equal "webhook timestamp is outside the allowed window", error.message
  end

  private

  def signature_for(raw_body, timestamp, secret)
    digest = OpenSSL::HMAC.hexdigest("sha256", secret, "#{timestamp}.#{raw_body}")
    "sha256=#{digest}"
  end
end
