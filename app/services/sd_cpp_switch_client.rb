# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class SdCppSwitchClient
  class Error < StandardError; end

  def initialize(
    base_url: Rails.application.config.x.nyoy.sd_cpp_switchd_url,
    token: Rails.application.config.x.nyoy.sd_cpp_switchd_token
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
    payload = { model: model }
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
    json = JSON.parse(res.body)

    unless res.is_a?(Net::HTTPSuccess) && json["ok"]
      raise Error, json["error"] || res.body
    end

    json
  end
end
