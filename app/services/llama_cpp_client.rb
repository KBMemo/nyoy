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

  def chat(messages:, temperature: 0.3, max_tokens: 512, response_format: nil, read_timeout: nil)
    payload = {
      model: @model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }
    payload[:response_format] = response_format if response_format.present?

    post_json("/v1/chat/completions", payload, read_timeout: read_timeout)
  end

  def message_text(response)
    self.class.message_text(response)
  end

  def self.message_text(response)
    message = response.dig("choices", 0, "message") || {}

    json_text = [message["content"], message["reasoning_content"]]
      .filter_map { |part| extract_json_text(part) }
      .max_by { |candidate| candidate[:score] }
      &.dig(:text)
    return json_text if json_text.present?

    content = message["content"].to_s.strip
    return content if content.present?

    reasoning = message["reasoning_content"].to_s.strip
    return "" if reasoning.blank?

    json_text = LlamaJsonParser.normalize(reasoning)
    return json_text if json_text.present?

    extract_text_from_reasoning(reasoning)
  end

  def self.extract_json_text(source)
    return nil if source.blank?

    normalized = LlamaJsonParser.normalize(source.to_s.strip)
    return nil if normalized.blank? || !normalized.start_with?("{")

    begin
      parsed = LlamaJsonParser.parse(normalized)
      return { text: parsed.to_json, score: 100 + normalized.length }
    rescue LlamaJsonParser::Error
      parsed = LlamaJsonParser.repair_truncated(normalized)
      { text: parsed.to_json, score: 50 + normalized.length }
    end
  rescue LlamaJsonParser::Error
    nil
  end

  def self.message_sources(response)
    message = response.dig("choices", 0, "message") || {}
    [message["content"], message["reasoning_content"]]
      .map { |part| part.to_s.strip }
      .reject(&:blank?)
      .uniq
  end

  def self.extract_text_from_reasoning(reasoning)
    if (match = reasoning.match(/["']([^"'\n]{3,})["']/))
      return match[1].strip
    end

    reasoning.lines.map(&:strip).reject do |line|
      line.empty? ||
        line.start_with?("*", "-", "#") ||
        line.match?(/\A(Input|Task|Translation|Constraint|Output|Standard|More descriptive):/i)
    end.last.to_s
  end

  private

  def post_json(path, payload, read_timeout: nil)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(payload)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = read_timeout || Rails.application.config.x.nyoy.llama_read_timeout

    res = http.request(req)
    json = JSON.parse(res.body)

    unless res.is_a?(Net::HTTPSuccess)
      raise Error, json["error"]&.dig("message") || res.body
    end

    json
  rescue Net::ReadTimeout, Timeout::Error
    raise Error, "llama.cpp read timeout (#{http.read_timeout}s)"
  end
end
