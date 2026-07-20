# frozen_string_literal: true

require "test_helper"

class LlamaServerReconciliationJobTest < ActiveJob::TestCase
  test "runs reconciliation for enabled switchd" do
    called = false
    original = LlamaServerReconciler.instance_method(:call)
    LlamaServerReconciler.define_method(:call) { called = true }

    assert_nothing_raised { LlamaServerReconciliationJob.perform_now }

    assert called
  ensure
    LlamaServerReconciler.define_method(:call, original) if defined?(original)
  end

  test "skips when switchd is disabled" do
    service_connections(:llama_switchd).update!(enabled: false)
    original = LlamaServerReconciler.method(:new)
    LlamaServerReconciler.define_singleton_method(:new) { |*| flunk("must not reconcile") }

    assert_nothing_raised { LlamaServerReconciliationJob.perform_now }
  ensure
    LlamaServerReconciler.define_singleton_method(:new, original) if defined?(original)
  end

  test "queues alert delivery when webhook is configured" do
    reconciliation = service_connections(:llama_switchd).llama_server_reconciliations.create!(
      status: "warning",
      checked_at: Time.current
    )
    original_url = Rails.application.config.x.nyoy.llama_server_alert_webhook_url
    original_call = LlamaServerReconciler.instance_method(:call)
    Rails.application.config.x.nyoy.llama_server_alert_webhook_url = "https://alerts.example.test/hook"
    LlamaServerReconciler.define_method(:call) { reconciliation }

    assert_enqueued_with(job: LlamaServerAlertJob, args: [ reconciliation.id ]) do
      LlamaServerReconciliationJob.perform_now
    end
  ensure
    Rails.application.config.x.nyoy.llama_server_alert_webhook_url = original_url
    LlamaServerReconciler.define_method(:call, original_call) if defined?(original_call)
  end
end
