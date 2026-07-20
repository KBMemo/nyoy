# frozen_string_literal: true

class LlamaSwitchdConnectionSync
  def initialize(connection)
    @connection = connection
  end

  def call
    manager = @connection.manager_connection
    raise LlamaSwitchdClient::Error, "switchd server が紐付けられていません" unless manager && @connection.managed_server_id.present?

    payload = LlamaSwitchdClient.new(base_url: manager.base_url, api_token: manager.api_token)
                                .get_server(@connection.managed_server_id)
    server = payload["server"]
    raise LlamaSwitchdClient::Error, "llama-switchd API 応答に server 情報がありません" unless server.is_a?(Hash)

    @connection.update!(
      base_url: data_plane_url(manager.base_url, server.fetch("port")),
      server_model: server.fetch("alias")
    )
    @connection
  end

  private

  def data_plane_url(control_url, port)
    uri = URI.parse(control_url)
    uri.path = ""
    uri.query = nil
    uri.fragment = nil
    uri.port = Integer(port)
    uri.to_s.sub(%r{/\z}, "")
  rescue URI::InvalidURIError, ArgumentError, TypeError => e
    raise LlamaSwitchdClient::Error, "llama-server URL を構成できません: #{e.message}"
  end
end
