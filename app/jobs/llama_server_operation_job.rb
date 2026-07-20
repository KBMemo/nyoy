# frozen_string_literal: true

class LlamaServerOperationJob < ApplicationJob
  queue_as :default

  def perform(operation_id)
    operation = LlamaServerOperation.find(operation_id)
    return unless mark_running(operation)

    connection = operation.service_connection
    client = LlamaSwitchdClient.new(base_url: connection.base_url, api_token: connection.api_token)
    client.public_send("#{operation.action}_server", operation.managed_server_id)
    detail = client.get_server(operation.managed_server_id)
    operation.update!(
      status: "succeeded",
      response_snapshot: safe_snapshot(detail),
      finished_at: Time.current
    )
  rescue StandardError => e
    operation&.update!(status: "failed", error_message: e.message.to_s.first(2000), finished_at: Time.current)
  end

  private

  def mark_running(operation)
    operation.with_lock do
      return false unless operation.status == "queued"

      operation.update!(status: "running", started_at: Time.current)
    end
    true
  end

  def safe_snapshot(detail)
    server = detail["server"]
    return {} unless server.is_a?(Hash)

    server.slice(
      "id", "alias", "port", "state", "ready", "active", "enabled",
      "configured_revision", "launched_revision", "launched_at", "restart_required"
    )
  end
end
