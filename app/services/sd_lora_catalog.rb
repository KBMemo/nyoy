# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class SdLoraCatalog
  class Error < StandardError; end

  def initialize(client: SdCppClient.new)
    @client = client
  end

  def list
    @client.get_json("/sdapi/v1/loras").map { |entry| normalize(entry) }
  rescue SdCppClient::Error => e
    raise Error, e.message
  end

  private

  def normalize(entry)
    case entry
    when String
      { "name" => entry, "path" => entry }
    when Hash
      {
        "name" => entry["name"] || File.basename(entry["path"].to_s, ".safetensors"),
        "path" => entry["path"] || entry["name"]
      }
    else
      {}
    end
  end
end
