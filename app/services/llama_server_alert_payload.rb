# frozen_string_literal: true

class LlamaServerAlertPayload
  def self.call(reconciliation, policy: LlamaServerAlertPolicy.new(reconciliation))
    {
      event: "llama_server.reconciliation.#{policy.event}",
      environment: Rails.env,
      reconciliation_id: reconciliation.id,
      status: reconciliation.status,
      previous_status: policy.previous_status,
      checked_at: reconciliation.checked_at.iso8601,
      findings: reconciliation.findings,
      error_message: reconciliation.error_message,
      management_path: "/service_connections/llama_servers"
    }
  end
end
