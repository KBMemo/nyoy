# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class ServiceConnectionPropsFetcher
  class Error < StandardError; end

  Result = Data.define(:ok, :sampling, :raw_props, :message)

  def initialize(connection)
    @connection = connection
  end

  def call
    unless @connection.generative_model_endpoint?
      raise Error, "この接続種別はサンプリング取得に対応していません"
    end

    props = fetch_props
    sampling = LlmSamplingParams.from_props(props)
    Result.new(
      ok: true,
      sampling: sampling,
      raw_props: props,
      message: "サーバーの生成既定値を取得しました"
    )
  rescue Error => e
    Result.new(ok: false, sampling: LlmSamplingParams.from({}), raw_props: {}, message: e.message)
  end

  private

  def fetch_props
    uri = URI("#{normalized_base_url}/props")
    req = Net::HTTP::Get.new(uri)
    req["Accept"] = "application/json"
    token = @connection.api_token.presence
    req["Authorization"] = "Bearer #{token}" if token.present?

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = 10
    http.use_ssl = uri.scheme == "https"

    res = http.request(req)
    body = res.body.to_s
    raise Error, "props の取得に失敗しました（HTTP #{res.code}）" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(body)
  rescue JSON::ParserError
    raise Error, "props の応答が JSON ではありません"
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
    raise Error, "接続できませんでした（#{e.message}）"
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    raise Error, "タイムアウトしました"
  end

  def normalized_base_url
    @connection.base_url.to_s.sub(%r{/\z}, "")
  end
end
