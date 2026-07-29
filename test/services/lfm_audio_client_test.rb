# frozen_string_literal: true

require "test_helper"

class LfmAudioClientTest < ActiveSupport::TestCase
  test "health returns the service payload" do
    client = build_client
    response = json_response(status: 200, body: { status: "ok", capabilities: { speech: true } })
    client.define_singleton_method(:perform_request) do |_uri, _request|
      response
    end

    result = client.health

    assert_equal "ok", result["status"]
    assert_equal true, result.dig("capabilities", "speech")
  end

  test "transcribe sends an authenticated multipart request" do
    client = build_client
    captured = nil
    response = json_response(status: 200, body: { text: "文字起こし結果" })
    client.define_singleton_method(:perform_request) do |uri, request|
      captured = [ uri, request ]
      response
    end

    text = client.transcribe(io: StringIO.new("wav"), filename: "voice.wav", content_type: "audio/wav")

    assert_equal "文字起こし結果", text
    assert_equal "http://audio.example.test:10120/v1/audio/transcriptions", captured.first.to_s
    assert_equal "Bearer audio_token", captured.second["Authorization"]
    assert_includes captured.second.body_stream.read, "voice.wav"
  end

  test "synthesize returns WAV data" do
    client = build_client
    captured = nil
    client.define_singleton_method(:perform_request) do |_uri, request|
      captured = request
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response["Content-Type"] = "audio/wav"
      response.instance_variable_set(:@body, "wav-bytes")
      def response.body = @body
      response
    end

    audio = client.synthesize(text: "音声合成です")

    assert_equal "wav-bytes", audio.data
    assert_equal "audio/wav", audio.content_type
    assert_equal "Bearer audio_token", captured["Authorization"]
    assert_equal "音声合成です", JSON.parse(captured.body).fetch("input")
  end

  test "raises when the connection is not configured" do
    client = LfmAudioClient.new(base_url: "", api_token: "", model: "")

    assert_raises(LfmAudioClient::Error) { client.synthesize(text: "音声") }
  end

  private

  def build_client
    LfmAudioClient.new(
      base_url: "http://audio.example.test:10120",
      api_token: "audio_token",
      model: "LiquidAI/LFM2.5-Audio-1.5B-JP"
    )
  end

  def json_response(status:, body:)
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s).new("1.1", status.to_s, "OK")
    response.instance_variable_set(:@body, body.to_json)
    def response.body = @body
    response
  end
end
