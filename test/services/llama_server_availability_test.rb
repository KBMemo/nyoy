# frozen_string_literal: true

require "test_helper"

class LlamaServerAvailabilityTest < ActiveSupport::TestCase
  test "returns false for stopped server in fresh snapshot" do
    connection = bind_connection
    reconcile([ { "id" => "main", "ready" => false } ])

    assert_not LlamaServerAvailability.available?(connection, max_age: 7200)
  end

  test "returns true for ready server in fresh snapshot" do
    connection = bind_connection
    reconcile([ { "id" => "main", "ready" => true } ])

    assert LlamaServerAvailability.available?(connection, max_age: 7200)
  end

  test "fails open for stale snapshot" do
    connection = bind_connection
    reconciliation = reconcile([ { "id" => "main", "ready" => false } ])
    reconciliation.update!(checked_at: 3.hours.ago)

    assert LlamaServerAvailability.available?(connection, max_age: 7200)
  end

  test "does not filter unmanaged connection" do
    connection = service_connections(:llama_cpp)
    connection.update!(manager_connection: nil, managed_server_id: nil)

    assert LlamaServerAvailability.available?(connection, max_age: 7200)
  end

  private

  def bind_connection
    service_connections(:llama_cpp).tap do |connection|
      connection.update!(manager_connection: service_connections(:llama_switchd), managed_server_id: "main")
    end
  end

  def reconcile(snapshot)
    service_connections(:llama_switchd).llama_server_reconciliations.create!(
      status: "healthy",
      server_snapshot: snapshot,
      checked_at: Time.current
    )
  end
end
