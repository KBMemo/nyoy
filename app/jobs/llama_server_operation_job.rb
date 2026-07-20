# frozen_string_literal: true

class LlamaServerOperationJob < ApplicationJob
  queue_as :default

  def perform(operation_id)
    operation = LlamaServerOperation.find(operation_id)
    return unless mark_running(operation)

    connection = operation.service_connection
    client = LlamaSwitchdClient.new(base_url: connection.base_url, api_token: connection.api_token)
    detail = execute(client, operation)
    snapshot = safe_snapshot(detail)
    if operation.action.in?(%w[start restart])
      snapshot["runtime"] = LlamaServerRuntimeVerifier.new(connection).call(detail)
    end
    operation.update!(
      status: "succeeded",
      response_snapshot: snapshot,
      finished_at: Time.current
    )
  rescue StandardError => e
    attrs = { status: "failed", error_message: e.message.to_s.first(2000), finished_at: Time.current }
    attrs[:response_snapshot] = snapshot if snapshot.present?
    operation&.update!(attrs)
  end

  private

  def execute(client, operation)
    case operation.action
    when "create"
      client.create_server(id: operation.managed_server_id, values: operation.request_payload.fetch("values"))
      client.get_server(operation.managed_server_id)
    when "update"
      client.update_server(operation.managed_server_id, values: operation.request_payload.fetch("values"))
      client.get_server(operation.managed_server_id)
    when "delete"
      response = client.delete_server(operation.managed_server_id)
      { "server" => { "id" => response["id"], "deleted" => response["deleted"] } }
    else
      client.public_send("#{operation.action}_server", operation.managed_server_id)
      client.get_server(operation.managed_server_id)
    end
  end

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
      "configured_revision", "launched_revision", "launched_at", "restart_required", "deleted"
    )
  end
end
