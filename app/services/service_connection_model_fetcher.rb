# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class ServiceConnectionModelFetcher
  class Error < StandardError; end

  Result = Data.define(:ok, :models, :message)

  OPENAI_COMPAT_KEYS = %w[llama_cpp gpt_oss vision_llama embeddings].freeze
  OPENAI_API_KEYS = %w[openai].freeze

  def initialize(connection)
    @connection = connection
  end

  def call
    models = fetch_models
    message = models.any? ? "モデル #{models.size} 件を取得しました" : "モデル候補がありません"
    Result.new(ok: true, models: models, message: message)
  rescue Error => e
    Result.new(ok: false, models: [], message: e.message)
  end

  private

  def fetch_models
    if @connection.openai?
      fetch_openai_api_models
    elsif @connection.custom_llm? || OPENAI_COMPAT_KEYS.include?(@connection.key)
      fetch_openai_compatible_models
    elsif @connection.key == "sd_switchd"
      fetch_sd_switchd_models
    else
      raise Error, "この接続種別はモデル取得に対応していません"
    end
  end

  def fetch_openai_api_models
    token = @connection.api_token.presence || NyoyConnectionStore.api_token(:openai)
    raise Error, "OpenAI API キーが未設定です" if token.blank?

    response = perform_get(
      URI("#{normalized_base_url}/v1/models"),
      headers: { "Authorization" => "Bearer #{token}" }
    )
    raise Error, http_error_message(response, "モデル一覧") unless response[:status] == 200

    payload = JSON.parse(response[:body])
    OpenaiChatModels.filter(model_ids_from(payload))
  rescue JSON::ParserError
    raise Error, "モデル一覧の応答が JSON ではありません"
  end

  def fetch_openai_compatible_models
    response = perform_get(URI("#{normalized_base_url}/v1/models"))
    raise Error, http_error_message(response, "モデル一覧") unless response[:status] == 200

    payload = JSON.parse(response[:body])
    model_ids_from(payload)
  rescue JSON::ParserError
    raise Error, "モデル一覧の応答が JSON ではありません"
  end

  def fetch_sd_switchd_models
    token = @connection.api_token.presence || NyoyConnectionStore.api_token(:sd_switchd)
    raise Error, "API トークンが未設定です" if token.blank?

    response = perform_get(
      URI("#{normalized_base_url}/v1/status"),
      headers: { "Authorization" => "Bearer #{token}" }
    )
    raise Error, http_error_message(response, "ステータス") unless response[:status] == 200

    payload = JSON.parse(response[:body])
    candidates = [
      payload["current_model"],
      payload.dig("current", "model"),
      *Array(payload["models"]),
      *Array(payload["available_models"])
    ]
    candidates.filter_map(&:presence).uniq
  rescue JSON::ParserError
    raise Error, "switchd の応答が JSON ではありません"
  end

  def model_ids_from(payload)
    Array(payload["data"] || payload["models"])
      .filter_map { |entry| entry.is_a?(Hash) ? entry["id"] || entry["model"] : entry }
      .map(&:to_s)
      .filter_map(&:presence)
      .uniq
  end

  def normalized_base_url
    @connection.base_url.to_s.sub(%r{/\z}, "")
  end

  def perform_get(uri, headers: {}, open_timeout: 3, read_timeout: 10)
    req = Net::HTTP::Get.new(uri)
    headers.each { |key, value| req[key] = value }

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout
    http.use_ssl = uri.scheme == "https"

    res = http.request(req)
    { status: res.code.to_i, body: res.body.to_s }
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "タイムアウトしました（#{open_timeout + read_timeout} 秒以内に応答がありません）"
  end

  def http_error_message(response, label)
    body = response[:body].to_s.strip
    return "#{label}の取得に失敗しました（HTTP #{response[:status]}）" if body.blank?

    "#{label}の取得に失敗しました（HTTP #{response[:status]}: #{truncate(body)}）"
  end

  def truncate(text, max: 120)
    text.length <= max ? text : "#{text[0, max]}..."
  end
end
