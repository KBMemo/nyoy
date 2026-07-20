# frozen_string_literal: true

require "net/http"
require "uri"

class LlamaSwitchdClient
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      @status = status
      super(message)
    end
  end

  def initialize(base_url:, api_token:, open_timeout: 3, read_timeout: 10)
    @base_uri = URI.parse(base_url.to_s)
    @api_token = api_token.to_s
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    validate_configuration!
  rescue URI::InvalidURIError => e
    raise Error, "llama-switchd URL が不正です: #{e.message}"
  end

  def health
    request_json("/health", authenticated: false)
  end

  def list_servers
    payload = request_json("/v1/servers")
    array_value(payload, "servers")
  end

  def list_models
    payload = request_json("/v1/models")
    array_value(payload, "models")
  end

  def get_server(id)
    request_json("/v1/servers/#{escape_path_component(id)}")
  end

  private

  def validate_configuration!
    unless @base_uri.is_a?(URI::HTTP) && @base_uri.host.present?
      raise Error, "llama-switchd URL は http:// または https:// で指定してください"
    end
    raise Error, "llama-switchd の API トークンが未設定です" if @api_token.blank?
  end

  def request_json(path, authenticated: true)
    uri = @base_uri.dup
    uri.path = [ @base_uri.path.to_s.sub(%r{/\z}, ""), path ].join
    uri.query = nil
    uri.fragment = nil

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{@api_token}" if authenticated

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    response = http.request(request)
    payload = JSON.parse(response.body)

    unless response.is_a?(Net::HTTPSuccess) && payload.is_a?(Hash) && payload["ok"] == true
      message = payload.is_a?(Hash) ? payload["error"].presence : nil
      raise Error.new("llama-switchd API エラー（HTTP #{response.code}）: #{message || '応答が不正です'}", status: response.code.to_i)
    end

    payload
  rescue JSON::ParserError
    raise Error, "llama-switchd API が不正な JSON を返しました"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => e
    raise Error, "llama-switchd に接続できません: #{e.message}"
  end

  def array_value(payload, key)
    value = payload[key]
    raise Error, "llama-switchd API 応答に #{key} 配列がありません" unless value.is_a?(Array)

    value
  end

  def escape_path_component(value)
    URI.encode_www_form_component(value.to_s).gsub("+", "%20")
  end
end
