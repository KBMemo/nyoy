# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class ServiceConnectionProbe
  class Error < StandardError; end

  Result = Data.define(:ok, :message, :latency_ms)

  OPENAI_COMPAT_KEYS = %w[llama_cpp gpt_oss vision_llama embeddings].freeze

  def initialize(connection)
    @connection = connection
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    message = probe!
    latency_ms = elapsed_ms(started)
    Result.new(ok: true, message: message, latency_ms: latency_ms)
  rescue Error => e
    Result.new(ok: false, message: e.message, latency_ms: elapsed_ms(started))
  end

  private

  def probe!
    case @connection.key
    when *OPENAI_COMPAT_KEYS
      probe_openai_compatible
    when "sd_cpp"
      probe_sd_cpp
    when "sd_switchd"
      probe_sd_switchd
    else
      raise Error, "不明な接続種別です"
    end
  end

  def probe_openai_compatible
    base = normalized_base_url
    health = perform_get(URI("#{base}/health"))
    if health[:status] == 200
      return "サーバーに接続できました（/health）"
    end

    models = perform_get(URI("#{base}/v1/models"))
    raise Error, http_error_message(models, "モデル一覧") unless models[:status] == 200

    payload = JSON.parse(models[:body])
    count = Array(payload["data"] || payload["models"]).size
    detail = count.positive? ? "モデル #{count} 件" : "応答あり"
    model_hint = matching_model_name(payload)
    [detail, model_hint].compact.join(" / ")
  rescue JSON::ParserError
    raise Error, "モデル一覧の応答が JSON ではありません"
  end

  def probe_sd_cpp
    response = perform_get(URI("#{normalized_base_url}/sdapi/v1/samplers"))
    raise Error, http_error_message(response, "サンプラー一覧") unless response[:status] == 200

    payload = JSON.parse(response[:body])
    count = payload.is_a?(Array) ? payload.size : 0
    count.positive? ? "サンプラー #{count} 件を取得しました" : "サーバーに接続できました"
  rescue JSON::ParserError
    raise Error, "sd.cpp の応答が JSON ではありません"
  end

  def probe_sd_switchd
    token = @connection.api_token.presence || NyoyConnectionStore.api_token(:sd_switchd)
    raise Error, "API トークンが未設定です" if token.blank?

    response = perform_get(
      URI("#{normalized_base_url}/v1/status"),
      headers: { "Authorization" => "Bearer #{token}" }
    )
    raise Error, http_error_message(response, "ステータス") unless response[:status] == 200

    payload = JSON.parse(response[:body])
    raise Error, payload["error"].presence || "switchd がエラーを返しました" unless payload["ok"]

    current = payload["current_model"].presence || payload.dig("current", "model")
    current.present? ? "接続できました（現在のモデル: #{current}）" : "接続できました"
  rescue JSON::ParserError
    raise Error, "switchd の応答が JSON ではありません"
  end

  def matching_model_name(payload)
    return unless @connection.server_model.present?

    models = Array(payload["data"] || payload["models"])
    ids = models.filter_map { |entry| entry["id"] || entry["model"] }
    return unless ids.any?

    ids.include?(@connection.server_model) ? "設定モデル #{@connection.server_model} を確認" : "設定モデル #{@connection.server_model} は一覧にありません"
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

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end
end
