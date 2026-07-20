# frozen_string_literal: true

class LlamaServerReconciler
  SNAPSHOT_KEYS = %w[id alias port state ready active enabled restart_required].freeze

  def initialize(connection, client: nil, runtime_probe: nil)
    @connection = connection
    @client = client || LlamaSwitchdClient.new(base_url: connection.base_url, api_token: connection.api_token)
    @runtime_probe = runtime_probe || LlamaServerRuntimeProbe.new(
      control_url: connection.base_url,
      public_host: connection.llama_switchd_settings.public_host
    )
  end

  def call
    servers = @client.list_servers
    runtimes = @runtime_probe.call(servers)
    findings = bound_connections.flat_map { |connection| findings_for(connection, servers, runtimes) }
    findings.concat(unbound_findings)
    findings.concat(restart_findings(servers))
    reconciliation = @connection.llama_server_reconciliations.create!(
      status: findings.empty? ? "healthy" : "warning",
      findings: findings,
      server_snapshot: servers.map { |server| server.slice(*SNAPSHOT_KEYS) },
      checked_at: Time.current
    )
    prune_history
    reconciliation
  rescue StandardError => e
    @connection.llama_server_reconciliations.create!(
      status: "failed",
      findings: [],
      server_snapshot: [],
      error_message: e.message.to_s.first(2000),
      checked_at: Time.current
    )
  end

  private

  def bound_connections
    @connection.managed_connections.enabled.ordered
  end

  def managed_candidates
    keys = (ServiceConnection::CHAT_BUILTIN_KEYS - [ "openai" ]) + %w[vision_llama embeddings]
    ServiceConnection.enabled.where(key: keys).or(ServiceConnection.enabled.custom_llms).ordered
  end

  def unbound_findings
    managed_candidates.where(manager_connection_id: nil).map do |connection|
      finding("connection_unbound", connection, "有効なローカル接続がswitchd serverに紐付けられていません", usage_labels(connection))
    end
  end

  def findings_for(connection, servers, runtimes)
    server = servers.find { |item| item["id"] == connection.managed_server_id }
    usages = usage_labels(connection)
    return [ finding("server_missing", connection, "紐付け先serverがswitchdにありません", usages) ] unless server

    findings = []
    expected_port = URI.parse(connection.base_url).port
    if server["port"].to_i != expected_port
      findings << finding("port_drift", connection, "portがNyoy=#{expected_port} / switchd=#{server['port']}です", usages)
    end
    if server["alias"].to_s != connection.server_model.to_s
      findings << finding("alias_drift", connection, "AliasがNyoy=#{connection.server_model} / switchd=#{server['alias']}です", usages)
    end
    unless server["ready"]
      findings << finding("server_not_ready", connection, "server状態は#{server['state']}です", usages)
    end
    runtime = runtimes[server["id"]]
    if runtime&.error.present?
      findings << finding("runtime_probe_failed", connection, "Runtime情報を取得できません: #{runtime.error}", usages)
    elsif runtime && runtime.model_alias.to_s != server["alias"].to_s
      findings << finding(
        "runtime_alias_drift",
        connection,
        "Runtime Aliasがswitchd=#{server['alias']} / runtime=#{runtime.model_alias}です",
        usages
      )
    end
    findings
  rescue URI::InvalidURIError
    [ finding("invalid_url", connection, "Nyoy接続URLが不正です", usages) ]
  end

  def restart_findings(servers)
    servers.filter_map do |server|
      next unless server["restart_required"]

      {
        "code" => "restart_required",
        "server_id" => server["id"],
        "message" => "定義変更を反映するには再起動が必要です",
        "usages" => bound_connections.where(managed_server_id: server["id"]).flat_map { |connection| usage_labels(connection) }.uniq
      }
    end
  end

  def finding(code, connection, message, usages)
    {
      "code" => code,
      "connection_key" => connection.key,
      "server_id" => connection.managed_server_id,
      "message" => message,
      "usages" => usages
    }
  end

  def usage_labels(connection)
    LlamaServerUsageResolver.labels_for(connection)
  end

  def prune_history
    max_count = [ Rails.application.config.x.nyoy.llama_server_reconciliation_max_count.to_i, 1 ].max
    ids = @connection.llama_server_reconciliations.recent.offset(max_count).pluck(:id)
    @connection.llama_server_reconciliations.where(id: ids).delete_all if ids.any?
  end
end
