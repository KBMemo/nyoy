# frozen_string_literal: true

class LlamaSwitchdInventory
  Result = Struct.new(:servers, :models, :connections, keyword_init: true)
  ConnectionComparison = Struct.new(
    :connection,
    :server,
    :port_matches,
    :alias_matches,
    :status,
    keyword_init: true
  )

  def initialize(connection, client: nil)
    @connection = connection
    @client = client || LlamaSwitchdClient.new(
      base_url: connection.base_url,
      api_token: connection.api_token
    )
  end

  def call
    servers = @client.list_servers
    Result.new(
      servers: servers,
      models: @client.list_models,
      connections: managed_connections.map { |connection| compare(connection, servers) }
    )
  end

  private

  def managed_connections
    keys = (ServiceConnection::CHAT_BUILTIN_KEYS - [ "openai" ]) + %w[vision_llama embeddings]
    ServiceConnection.where(key: keys).or(ServiceConnection.custom_llms).ordered
  end

  def compare(connection, servers)
    port = connection_port(connection)
    bound_server = servers.find { |server| server["id"] == connection.managed_server_id } if connection.managed_server_id.present?
    port_server = servers.find { |server| server["port"].to_i == port } if port
    alias_server = servers.find { |server| server["alias"].to_s == connection.server_model.to_s } if connection.server_model.present?
    server = bound_server || port_server || alias_server
    port_matches = server.present? && server["port"].to_i == port
    alias_matches = server.present? && server["alias"].to_s == connection.server_model.to_s

    ConnectionComparison.new(
      connection: connection,
      server: server,
      port_matches: port_matches,
      alias_matches: alias_matches,
      status: comparison_status(server, port_matches, alias_matches)
    )
  end

  def connection_port(connection)
    uri = URI.parse(connection.base_url)
    uri.port
  rescue URI::InvalidURIError
    nil
  end

  def comparison_status(server, port_matches, alias_matches)
    return :unmatched unless server
    return :exact if port_matches && alias_matches
    return :port_only if port_matches
    return :alias_only if alias_matches

    :unmatched
  end
end
