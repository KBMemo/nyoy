# frozen_string_literal: true

class McpController < ActionController::API
  before_action :require_mcp_enabled!
  before_action :authenticate!

  def entry
    server = Mcp::ServerBuilder.build
    transport = build_transport(server)
    status, headers, body = transport.handle_request(request)

    response.status = status
    headers.each { |key, value| response.headers[key] = value }
    self.response_body = body
  end

  private

  def require_mcp_enabled!
    head :not_found unless Mcp.enabled?
  end

  def authenticate!
    token = bearer_token
    expected = Mcp.api_token.to_s

    return if token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)

    response.headers["WWW-Authenticate"] = 'Bearer realm="nyoy-mcp", charset="UTF-8"'
    head :unauthorized
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header.match?(/\ABearer /i)

    header.split(" ", 2).last&.strip
  end

  def build_transport(server)
    MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      enable_json_response: json_response_requested?,
      dns_rebinding_protection: Rails.application.config.x.nyoy.mcp_dns_rebinding_protection
    )
  end

  def json_response_requested?
    accept = request.headers["Accept"].to_s
    accept.include?("application/json") && !accept.include?("text/event-stream")
  end
end
