# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class SdSamplerCatalog
  class Error < StandardError; end

  def initialize(client: SdCppClient.new)
    @client = client
  end

  def names
    entries = @client.get_json("/sdapi/v1/samplers")
    entries.filter_map { |entry| entry.is_a?(Hash) ? entry["name"] : entry }.uniq
  rescue SdCppClient::Error => e
    raise Error, e.message
  end
end
