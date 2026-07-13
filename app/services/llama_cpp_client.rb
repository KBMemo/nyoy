# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class LlamaCppClient
  class Error < StandardError; end

  def initialize(
    base_url: NyoyConnectionStore.url(:llama_cpp),
    model: NyoyConnectionStore.server_model(:llama_cpp),
    api_token: nil
  )
    @base_url = base_url.sub(%r{/\z}, "")
    @model = model
    @api_token = api_token
  end

  def chat(messages:, temperature: 0.3, max_tokens: 512, response_format: nil, chat_template_kwargs: nil,
           sampling: nil, top_p: nil, top_k: nil, min_p: nil, presence_penalty: nil, frequency_penalty: nil,
           repeat_penalty: nil, read_timeout: nil)
    payload = {
      model: @model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }
    payload[:response_format] = response_format if response_format.present?
    payload[:chat_template_kwargs] = chat_template_kwargs if chat_template_kwargs.present?

    sampling_params = normalize_sampling(
      sampling,
      top_p: top_p,
      top_k: top_k,
      min_p: min_p,
      presence_penalty: presence_penalty,
      frequency_penalty: frequency_penalty,
      repeat_penalty: repeat_penalty
    )
    sampling_params.each { |key, value| payload[key] = value }

    post_json("/v1/chat/completions", payload, read_timeout: read_timeout)
  end

  def props
    get_json("/props")
  end

  def total_slots
    value = props["total_slots"]
    count = Integer(value)
    count.positive? ? count : nil
  rescue ArgumentError, TypeError
    nil
  end

  def message_text(response)
    self.class.message_text(response)
  end

  def self.message_text(response)
    message = response.dig("choices", 0, "message") || {}
    choice = response.dig("choices", 0) || {}

    content = normalize_message_content(message["content"])
    reasoning = normalize_message_content(message["reasoning_content"])
    legacy = choice["text"].to_s.strip

    json_text = [content, reasoning]
      .filter_map { |part| extract_json_text(part) }
      .max_by { |candidate| candidate[:score] }
      &.dig(:text)
    return json_text if json_text.present?

    return content if content.present?
    return legacy if legacy.present?

    return "" if reasoning.blank?

    json_text = LlamaJsonParser.normalize(reasoning)
    return json_text if json_text.present?

    extract_text_from_reasoning(reasoning)
  end

  def self.normalize_message_content(content)
    case content
    when Array
      content.filter_map do |part|
        next unless part.is_a?(Hash)

        part["text"].presence || part["content"].presence
      end.join("\n").strip
    when String
      content.strip
    else
      content.to_s.strip
    end
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

  def normalize_sampling(sampling, **explicit)
    params = {}
    if sampling.respond_to?(:to_request_params)
      params.merge!(sampling.to_request_params)
    elsif sampling.is_a?(Hash)
      params.merge!(LlmSamplingParams.from(sampling).to_request_params)
    end

    explicit.each do |key, value|
      next if value.nil?

      params[key.to_sym] = value
    end
    params
  end

  def get_json(path)
    request_json(Net::HTTP::Get, path)
  end

  def post_json(path, payload, read_timeout: nil)
    request_json(Net::HTTP::Post, path, payload: payload, read_timeout: read_timeout)
  end

  def request_json(request_class, path, payload: nil, read_timeout: nil)
    uri = URI("#{@base_url}#{path}")
    req = request_class.new(uri)
    if payload
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(payload)
    end
    req["Accept"] = "application/json"
    req["Authorization"] = "Bearer #{@api_token}" if @api_token.present?

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = read_timeout || (payload ? Rails.application.config.x.nyoy.llama_read_timeout : 5)
    http.use_ssl = uri.scheme == "https"

    res = http.request(req)
    body = res.body.to_s
    json = body.present? ? JSON.parse(body) : {}

    unless res.is_a?(Net::HTTPSuccess)
      raise Error, json["error"]&.dig("message") || json["error"].presence || body.presence || "HTTP #{res.code}"
    end

    json
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "llama.cpp に接続できませんでした（#{e.message}）"
  rescue Net::ReadTimeout, Timeout::Error
    raise Error, "llama.cpp read timeout (#{http.read_timeout}s)"
  rescue JSON::ParserError
    snippet = body.to_s.strip
    snippet = "#{snippet[0, 120]}..." if snippet.length > 120
    detail = snippet.present? ? "（#{snippet}）" : ""
    raise Error, "llama.cpp の応答が JSON ではありません#{detail}"
  end
end
