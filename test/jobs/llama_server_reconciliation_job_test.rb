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
end
