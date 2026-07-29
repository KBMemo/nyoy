# frozen_string_literal: true

require "test_helper"

class Api::AudioControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "audio_api_test_token"
    Rails.application.config.x.nyoy.mcp_api_token = @token
  end

  teardown do
    Rails.application.config.x.nyoy.mcp_api_token = ENV["MCP_API_TOKEN"]
  end

  test "requires a bearer token" do
    get "/api/audio/health"

    assert_response :unauthorized
  end

  test "proxies health through the audio client" do
    client = fake_client(health: { "status" => "ok", "capabilities" => { "speech" => true } })

    with_client(client) do
      get "/api/audio/health", headers: authorization
    end

    assert_response :success
    assert_equal true, response.parsed_body.dig("capabilities", "speech")
  end

  test "proxies a multipart transcription request" do
    client = fake_client(transcribe: "文字起こし結果")
    upload = Rack::Test::UploadedFile.new(StringIO.new("wav"), "audio/wav", original_filename: "voice.wav")

    with_client(client) do
      post "/api/audio/transcriptions", params: { file: upload, language: "ja" }, headers: authorization
    end

    assert_response :success
    assert_equal "文字起こし結果", response.parsed_body["text"]
  end

  test "returns synthesized WAV data" do
    audio = LfmAudioClient::Audio.new(data: "wav-bytes", content_type: "audio/wav", filename: "speech.wav")
    client = fake_client(synthesize: audio)

    with_client(client) do
      post "/api/audio/speech", params: { input: "音声合成です" }, headers: authorization
    end

    assert_response :success
    assert_equal "audio/wav", response.media_type
    assert_equal "wav-bytes", response.body
  end

  test "returns upstream client errors without exposing a 500" do
    client = Object.new
    client.define_singleton_method(:health) { raise LfmAudioClient::Error, "audio unavailable" }

    with_client(client) do
      get "/api/audio/health", headers: authorization
    end

    assert_response :service_unavailable
    assert_equal "audio unavailable", response.parsed_body["error"]
  end

  private

  def authorization
    { "Authorization" => "Bearer #{@token}" }
  end

  def fake_client(health: nil, transcribe: nil, synthesize: nil)
    client = Object.new
    client.define_singleton_method(:health) { health }
    client.define_singleton_method(:transcribe) { |**| transcribe }
    client.define_singleton_method(:synthesize) { |**| synthesize }
    client
  end

  def with_client(client)
    original = LfmAudioClient.method(:new)
    LfmAudioClient.singleton_class.define_method(:new) { |*| client }
    yield
  ensure
    LfmAudioClient.singleton_class.define_method(:new, original)
  end
end
