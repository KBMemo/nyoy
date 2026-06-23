# frozen_string_literal: true

require "base64"
require "net/http"
require "json"
require "uri"

class SdCppClient
  class Error < StandardError; end

  def initialize(base_url: Rails.application.config.x.nyoy.sd_cpp_url)
    @base_url = base_url.sub(%r{/\z}, "")
  end

  def txt2img(prompt:, negative_prompt: "", width: 512, height: 512, steps: 20, cfg_scale: 7.0, seed: -1)
    json = post_json(
      "/sdapi/v1/txt2img",
      prompt: prompt,
      negative_prompt: negative_prompt,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      seed: seed
    )

    image_b64 = json.fetch("images", []).first
    raise Error, "no image returned" if image_b64.blank?

    Base64.decode64(image_b64)
  end

  private

  def post_json(path, payload)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(payload)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 600

    res = http.request(req)
    body = res.body.to_s

    json = JSON.parse(body)
    unless res.is_a?(Net::HTTPSuccess)
      raise Error, json["error"] || body
    end

    json
  rescue JSON::ParserError
    raise Error, body.presence || "invalid response from sd-server"
  end
end
