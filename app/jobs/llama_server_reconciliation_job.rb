# frozen_string_literal: true

class LlamaServerReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    connection = ServiceConnection.find_by(key: "llama_switchd", enabled: true)
    return unless connection

    LlamaServerReconciler.new(connection).call
  end
end
