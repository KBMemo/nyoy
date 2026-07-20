# frozen_string_literal: true

require "test_helper"

class LlamaServerMaintenanceJobTest < ActiveJob::TestCase
  setup do
    config = Rails.application.config.x.nyoy
    @original_retention = config.llama_server_operation_retention_days
    @original_operation_max = config.llama_server_operation_max_count
    @original_reconciliation_max = config.llama_server_reconciliation_max_count
    config.llama_server_operation_retention_days = 30
    config.llama_server_operation_max_count = 2
    config.llama_server_reconciliation_max_count = 2
  end

  teardown do
    config = Rails.application.config.x.nyoy
    config.llama_server_operation_retention_days = @original_retention
    config.llama_server_operation_max_count = @original_operation_max
    config.llama_server_reconciliation_max_count = @original_reconciliation_max
  end

  test "prunes completed history while preserving active operations" do
    connection = service_connections(:llama_switchd)
    old = create_operation(connection, "old", status: "succeeded", finished_at: 31.days.ago)
    active = create_operation(connection, "active", status: "running", finished_at: nil)
    recent = 3.times.map do |index|
      create_operation(connection, "recent-#{index}", status: "succeeded", finished_at: (index + 1).minutes.ago)
    end
    reconciliations = 3.times.map do |index|
      connection.llama_server_reconciliations.create!(
        status: "healthy",
        checked_at: (index + 1).minutes.ago
      )
    end

    LlamaServerMaintenanceJob.perform_now

    assert_not LlamaServerOperation.exists?(old.id)
    assert LlamaServerOperation.exists?(active.id)
    assert_equal 2, connection.llama_server_operations.where(id: recent.map(&:id)).count
    assert_equal 2, connection.llama_server_reconciliations.where(id: reconciliations.map(&:id)).count
  end

  private

  def create_operation(connection, server_id, status:, finished_at:)
    connection.llama_server_operations.create!(
      managed_server_id: server_id,
      action: "start",
      status: status,
      started_at: finished_at || Time.current,
      finished_at: finished_at
    )
  end
end
