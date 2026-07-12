# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class SdCppSwitchClient
  class Error < StandardError; end

  def initialize(
    base_url: NyoyConnectionStore.url(:sd_switchd),
    token: NyoyConnectionStore.api_token(:sd_switchd)
  )
    @base_url = base_url.sub(%r{/\z}, "")
    @token = token
  end

  def configured?
    @token.present?
  end

  def current
    get_json("/v1/current")
  end

  def models
    get_json("/v1/models")
  end

  def status
    get_json("/v1/status")
  end

  def switch(model, lora: nil)
    switch_key = model.presence
    raise Error, "モデル切替キーが未設定です" if switch_key.blank?

    payload = { model: switch_key }
    payload[:lora] = lora if lora.present?
    post_json("/v1/switch", payload)
  end

  def restart(model, lora: nil)
    payload = { model: model }
    payload[:lora] = lora if lora.present?
    post_json("/v1/restart", payload)
  end

  def stop
    post_json("/v1/stop", {})
  end

  private

  def get_json(path)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Get.new(uri)
    request_json(uri, req)
  end

  def post_json(path, payload)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(payload)
    request_json(uri, req)
  end

  def request_json(uri, req)
    unless configured?
      raise Error, "SDCPP_SWITCHD_TOKEN is not set"
    end

    req["Authorization"] = "Bearer #{@token}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = 120

    res = http.request(req)
    body = res.body.to_s
    json = body.present? ? JSON.parse(body) : {}

    unless res.is_a?(Net::HTTPSuccess) && json["ok"]
      raise Error, json["error"] || body.presence || "HTTP #{res.code}"
    end

    json
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "sd-switchd に接続できませんでした（#{e.message}）"
  rescue JSON::ParserError
    raise Error, body.presence || "invalid response from sd-switchd"
  end
end
