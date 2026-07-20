# frozen_string_literal: true

class LlamaServerReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    connection = ServiceConnection.find_by(key: "llama_switchd", enabled: true)
    return unless connection

    reconciliation = LlamaServerReconciler.new(connection).call
    LlamaServerAlertJob.perform_later(reconciliation.id) if LlamaServerAlert.enabled?
  end
end
