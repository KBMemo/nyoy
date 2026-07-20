# frozen_string_literal: true

class LlamaServerAlertPolicy
  def initialize(reconciliation)
    @reconciliation = reconciliation
  end

  def notify?
    return !@reconciliation.healthy? unless previous
    return !previous.healthy? if @reconciliation.healthy?
    return previous.status != "failed" if @reconciliation.status == "failed"

    previous.status != "warning" || warning_fingerprint(previous) != warning_fingerprint(@reconciliation)
  end

  def event
    @reconciliation.healthy? ? "recovered" : @reconciliation.status
  end

  def previous_status
    previous&.status
  end

  private

  def previous
    @previous ||= @reconciliation.service_connection.llama_server_reconciliations
      .where("checked_at < ? OR (checked_at = ? AND id < ?)", @reconciliation.checked_at, @reconciliation.checked_at, @reconciliation.id)
      .recent
      .first
  end

  def warning_fingerprint(reconciliation)
    reconciliation.findings.map do |finding|
      finding.slice("code", "connection_key", "server_id")
    end.sort_by { |finding| finding.values_at("code", "connection_key", "server_id").map(&:to_s) }
  end
end
