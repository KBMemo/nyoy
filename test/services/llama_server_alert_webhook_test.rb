# frozen_string_literal: true

require "test_helper"

class LlamaServerAlertWebhookTest < ActiveSupport::TestCase
  test "posts a typed alert with authentication and idempotency key" do
    previous = create_reconciliation("healthy")
    reconciliation = create_reconciliation("warning", findings: [ { "code" => "alias_drift" } ])
    request = nil
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_| }
    http.define_singleton_method(:open_timeout=) { |_| }
    http.define_singleton_method(:read_timeout=) { |_| }
    http.define_singleton_method(:request) do |value|
      request = value
      Net::HTTPOK.new("1.1", "200", "OK")
    end

    with_http(http) do
      LlamaServerAlertWebhook.new(url: "https://alerts.example.test/hook", token: "secret").deliver(reconciliation)
    end

    payload = JSON.parse(request.body)
    assert_equal "Bearer secret", request["Authorization"]
    assert_equal "nyoy-llama-reconciliation-#{reconciliation.id}", request["Idempotency-Key"]
    assert_equal "llama_server.reconciliation.warning", payload["event"]
    assert_equal previous.status, payload["previous_status"]
    assert_equal [ { "code" => "alias_drift" } ], payload["findings"]
  end

  test "raises a typed error for an unsuccessful response" do
    reconciliation = create_reconciliation("warning")
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_| }
    http.define_singleton_method(:open_timeout=) { |_| }
    http.define_singleton_method(:read_timeout=) { |_| }
    http.define_singleton_method(:request) { |_| Net::HTTPServiceUnavailable.new("1.1", "503", "Unavailable") }

    error = assert_raises(LlamaServerAlertWebhook::Error) do
      with_http(http) { LlamaServerAlertWebhook.new(url: "https://alerts.example.test/hook").deliver(reconciliation) }
    end
    assert_equal "LLM server alert webhook returned HTTP 503", error.message
  end

  private

  def create_reconciliation(status, findings: [])
    service_connections(:llama_switchd).llama_server_reconciliations.create!(
      status: status,
      findings: findings,
      checked_at: Time.current + LlamaServerReconciliation.count.seconds
    )
  end

  def with_http(http)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| http }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end
end
