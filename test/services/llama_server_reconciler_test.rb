# frozen_string_literal: true

require "test_helper"

class LlamaServerReconcilerTest < ActiveSupport::TestCase
  test "records healthy snapshot for matching ready binding" do
    connection = bind_connection(:llama_cpp, server_id: "main", url: "http://balvenie:10010", model: "main-alias")
    ServiceConnection.where.not(id: [ connection.id, service_connections(:llama_switchd).id ]).update_all(enabled: false)
    server = {
      "id" => "main", "port" => 10010, "alias" => "main-alias", "state" => "ready",
      "ready" => true, "active" => true, "enabled" => true, "restart_required" => false,
      "source" => "/secret/model/path.gguf"
    }

    result = reconciler(servers: [ server ]).call

    assert_equal "healthy", result.status
    assert_empty result.findings
    assert_not result.server_snapshot.first.key?("source")
  end

  test "records drift readiness and restart findings with usage" do
    connection = bind_connection(:llama_cpp, server_id: "main", url: "http://balvenie:10010", model: "old-alias")
    AppSetting.instance.update!(default_chat_connection_key: connection.key)
    server = {
      "id" => "main", "port" => 10011, "alias" => "new-alias", "state" => "stopped",
      "ready" => false, "active" => false, "enabled" => true, "restart_required" => true
    }

    result = reconciler(servers: [ server ]).call
    codes = result.findings.pluck("code")

    assert_equal "warning", result.status
    assert_includes codes, "port_drift"
    assert_includes codes, "alias_drift"
    assert_includes codes, "server_not_ready"
    assert_includes codes, "restart_required"
    assert result.findings.any? { |finding| finding["usages"].include?("既定Chat") }
    assert_equal "old-alias", connection.reload.server_model
  end

  test "records failed reconciliation when switchd is unavailable" do
    client = Object.new
    client.define_singleton_method(:list_servers) { raise LlamaSwitchdClient::Error, "unavailable" }

    result = LlamaServerReconciler.new(service_connections(:llama_switchd), client: client).call

    assert_equal "failed", result.status
    assert_equal "unavailable", result.error_message
  end

  test "warns about enabled unbound local connections but excludes OpenAI" do
    ServiceConnection.where.not(key: %w[llama_cpp openai llama_switchd]).update_all(enabled: false)
    service_connections(:llama_cpp).update!(manager_connection: nil, managed_server_id: nil, enabled: true)

    result = reconciler(servers: []).call
    unbound = result.findings.select { |finding| finding["code"] == "connection_unbound" }

    assert_equal [ "llama_cpp" ], unbound.pluck("connection_key")
  end

  private

  def bind_connection(name, server_id:, url:, model:)
    service_connections(name).tap do |connection|
      connection.update!(
        manager_connection: service_connections(:llama_switchd),
        managed_server_id: server_id,
        base_url: url,
        server_model: model,
        enabled: true
      )
    end
  end

  def reconciler(servers:)
    client = Object.new
    client.define_singleton_method(:list_servers) { servers }
    LlamaServerReconciler.new(service_connections(:llama_switchd), client: client)
  end
end
