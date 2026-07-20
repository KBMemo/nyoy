# frozen_string_literal: true

class LlamaServerAlertWebhook
  class Error < StandardError; end

  def initialize(url: LlamaServerAlert.webhook_url, token: LlamaServerAlert.webhook_token)
    @uri = URI.parse(url)
    @token = token
    validate_configuration!
  rescue URI::InvalidURIError
    raise Error, "LLM server alert webhook URL is invalid"
  end

  def deliver(reconciliation, policy: LlamaServerAlertPolicy.new(reconciliation))
    request = Net::HTTP::Post.new(@uri)
    request["Accept"] = "application/json"
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{@token}" if @token.present?
    request["Idempotency-Key"] = "nyoy-llama-reconciliation-#{reconciliation.id}"
    request.body = JSON.generate(payload(reconciliation, policy))

    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = @uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    response = http.request(request)
    return if response.is_a?(Net::HTTPSuccess)

    raise Error, "LLM server alert webhook returned HTTP #{response.code}"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
    raise Error, "LLM server alert webhook is unavailable: #{e.message}"
  end

  private

  def validate_configuration!
    return if @uri.is_a?(URI::HTTP) && @uri.host.present?

    raise Error, "LLM server alert webhook URL must use http or https"
  end

  def payload(reconciliation, policy)
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
