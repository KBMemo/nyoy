# frozen_string_literal: true

class LlamaServerMaintenanceJob < ApplicationJob
  queue_as :default

  def perform
    ServiceConnection.where(key: "llama_switchd").find_each do |connection|
      prune_operations(connection)
      prune_reconciliations(connection)
    end
  end

  private

  def prune_operations(connection)
    retention_days = [ Rails.application.config.x.nyoy.llama_server_operation_retention_days.to_i, 1 ].max
    max_count = [ Rails.application.config.x.nyoy.llama_server_operation_max_count.to_i, 1 ].max
    completed = connection.llama_server_operations.where.not(status: LlamaServerOperation::ACTIVE_STATUSES)
    completed.where("finished_at < ?", retention_days.days.ago).delete_all

    excess_ids = completed.order(created_at: :desc).offset(max_count).pluck(:id)
    completed.where(id: excess_ids).delete_all if excess_ids.any?
  end

  def prune_reconciliations(connection)
    max_count = [ Rails.application.config.x.nyoy.llama_server_reconciliation_max_count.to_i, 1 ].max
    excess_ids = connection.llama_server_reconciliations.recent.offset(max_count).pluck(:id)
    connection.llama_server_reconciliations.where(id: excess_ids).delete_all if excess_ids.any?
  end
end
