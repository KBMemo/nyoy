# frozen_string_literal: true

require "test_helper"

class LlamaServerReconciliationTest < ActiveSupport::TestCase
  test "requires switchd connection" do
    reconciliation = LlamaServerReconciliation.new(
      service_connection: service_connections(:llama_cpp),
      status: "healthy",
      checked_at: Time.current
    )

    assert_not reconciliation.valid?
    assert reconciliation.errors[:service_connection].any?
  end
end
