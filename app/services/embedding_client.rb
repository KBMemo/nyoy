# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class EmbeddingClient
  class Error < StandardError; end

  def initialize(
    base_url: NyoyConnectionStore.url(:embeddings),
    model: NyoyConnectionStore.server_model(:embeddings)
  )
    @base_url = base_url.sub(%r{/\z}, "")
    @model = model
  end

  def embed(input:)
    texts = Array(input)
    raise Error, "input required" if texts.empty?

    response = post_json(
      "/v1/embeddings",
      model: @model,
      input: texts.length == 1 ? texts.first : texts
    )

    data = Array(response["data"])
    raise Error, "empty embedding response" if data.empty?

    if texts.length == 1
      extract_vector(data.first)
    else
      data.sort_by { |entry| entry["index"] || 0 }.map { |entry| extract_vector(entry) }
    end
  end

  private

  def extract_vector(entry)
    vector = Array(entry["embedding"])
    raise Error, "embedding vector missing" if vector.empty?

    vector.map(&:to_f)
  end

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
      raise Error, json.dig("error", "message") || json["error"] || res.body
    end

    json
  end
end
