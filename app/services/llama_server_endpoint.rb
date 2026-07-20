# frozen_string_literal: true

class LlamaServerEndpoint
  class Error < StandardError; end

  def self.build(control_url:, port:, public_host: nil)
    uri = URI.parse(control_url)
    uri.host = public_host if public_host.present?
    uri.port = Integer(port)
    uri.path = ""
    uri.query = nil
    uri.fragment = nil
    uri.to_s.sub(%r{/\z}, "")
  rescue URI::InvalidURIError, URI::InvalidComponentError, ArgumentError, TypeError => e
    raise Error, "llama-server URL を構成できません: #{e.message}"
  end
end
