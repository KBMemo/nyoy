# frozen_string_literal: true

require "test_helper"

class LlamaServerAlertJobTest < ActiveJob::TestCase
  setup do
    @original_url = Rails.application.config.x.nyoy.llama_server_alert_webhook_url
    Rails.application.config.x.nyoy.llama_server_alert_webhook_url = "https://alerts.example.test/hook"
  end

  teardown do
    Rails.application.config.x.nyoy.llama_server_alert_webhook_url = @original_url
  end

  test "delivers a changed reconciliation" do
    create_reconciliation("healthy")
    warning = create_reconciliation("warning", findings: [ finding("server_not_ready") ])
    delivered = nil
    webhook = Object.new
    webhook.define_singleton_method(:deliver) { |reconciliation, **| delivered = reconciliation }

    with_webhook(webhook) { LlamaServerAlertJob.perform_now(warning.id) }

    assert_equal warning, delivered
  end

  test "does not deliver an unchanged reconciliation" do
    create_reconciliation("warning", findings: [ finding("server_not_ready") ])
    repeated = create_reconciliation("warning", findings: [ finding("server_not_ready") ])
    webhook = Object.new
    webhook.define_singleton_method(:deliver) { |*| flunk("must not deliver") }

    assert_nothing_raised { with_webhook(webhook) { LlamaServerAlertJob.perform_now(repeated.id) } }
  end

  private

  def create_reconciliation(status, findings: [])
    service_connections(:llama_switchd).llama_server_reconciliations.create!(
      status: status,
      findings: findings,
      checked_at: Time.current + LlamaServerReconciliation.count.seconds
    )
  end

  def finding(code)
    { "code" => code, "connection_key" => "llama_cpp", "server_id" => "main" }
  end

  def with_webhook(webhook)
    original = LlamaServerAlertWebhook.method(:new)
    LlamaServerAlertWebhook.define_singleton_method(:new) { webhook }
    yield
  ensure
    LlamaServerAlertWebhook.define_singleton_method(:new, original)
  end
end
