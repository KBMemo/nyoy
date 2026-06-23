# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class LlamaCppClient
  class Error < StandardError; end

  def initialize(
    base_url: Rails.application.config.x.nyoy.llama_cpp_url,
    model: Rails.application.config.x.nyoy.llama_model
  )
    @base_url = base_url.sub(%r{/\z}, "")
    @model = model
  end

  def chat(messages:, temperature: 0.3, max_tokens: 512)
    post_json(
      "/v1/chat/completions",
      model: @model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    )
  end

  private

  def post_json(path, payload)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(payload)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 120

    res = http.request(req)
    json = JSON.parse(res.body)

    unless res.is_a?(Net::HTTPSuccess)
      raise Error, json["error"]&.dig("message") || res.body
    end

    json
  end
end
