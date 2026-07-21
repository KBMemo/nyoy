# frozen_string_literal: true

class LlamaServerAlertJob < ApplicationJob
  queue_as :default

  retry_on LlamaServerAlertWebhook::Error, LlamaServerAlertZabbixSender::Error,
           wait: :polynomially_longer, attempts: 5

  def perform(reconciliation_id)
    return unless LlamaServerAlert.enabled?

    reconciliation = LlamaServerReconciliation.find(reconciliation_id)
    policy = LlamaServerAlertPolicy.new(reconciliation)
    return unless policy.notify?

    LlamaServerAlertWebhook.new.deliver(reconciliation, policy: policy) if LlamaServerAlert.webhook_enabled?
    LlamaServerAlertZabbixSender.new.deliver(reconciliation, policy: policy) if LlamaServerAlert.zabbix_enabled?
  end
end
