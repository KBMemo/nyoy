# frozen_string_literal: true

require "openssl"

class MemoRagWebhookSignature
  class Error < StandardError; end

  ALGORITHM = "sha256"
  MAX_CLOCK_SKEW = 5.minutes

  def self.verify!(raw_body:, timestamp:, signature:, secret: Rails.application.config.x.nyoy.memo_rag_webhook_secret)
    new(raw_body: raw_body, timestamp: timestamp, signature: signature, secret: secret).verify!
  end

  def initialize(raw_body:, timestamp:, signature:, secret:)
    @raw_body = raw_body.to_s
    @timestamp = timestamp.to_s
    @signature = signature.to_s
    @secret = secret.to_s
  end

  def verify!
    raise Error, "webhook secret is not configured" if @secret.blank?
    raise Error, "webhook timestamp is missing" if @timestamp.blank?
    raise Error, "webhook signature is missing" if @signature.blank?

    parsed_timestamp = parse_timestamp
    if (Time.current - parsed_timestamp).abs > MAX_CLOCK_SKEW
      raise Error, "webhook timestamp is outside the allowed window"
    end

    expected = "#{ALGORITHM}=#{digest}"
    return true if secure_compare(expected, @signature)

    raise Error, "webhook signature is invalid"
  end

  private

  def parse_timestamp
    Time.iso8601(@timestamp)
  rescue ArgumentError
    raise Error, "webhook timestamp is invalid"
  end

  def digest
    OpenSSL::HMAC.hexdigest(ALGORITHM, @secret, "#{@timestamp}.#{@raw_body}")
  end

  def secure_compare(expected, actual)
    return false unless expected.bytesize == actual.bytesize

    ActiveSupport::SecurityUtils.secure_compare(expected, actual)
  end
end
