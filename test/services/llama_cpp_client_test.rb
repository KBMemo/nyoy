# frozen_string_literal: true

require "test_helper"

class LlamaCppClientTest < ActiveSupport::TestCase
  test "total_slots reads props endpoint" do
    client = LlamaCppClient.new(base_url: "http://llama.test:8080")
    paths = []
    client.define_singleton_method(:get_json) do |path|
      paths << path
      { "total_slots" => 4, "model_path" => "model.gguf" }
    end

    assert_equal 4, client.total_slots
    assert_equal ["/props"], paths
  end

  test "extracts quoted text from reasoning content" do
    response = {
      "choices" => [
        {
          "message" => {
            "content" => "",
            "reasoning_content" => "Task: translate\n\"1girl, blue hair, sakura\""
          }
        }
      ]
    }

    assert_equal "1girl, blue hair, sakura", LlamaCppClient.message_text(response)
  end

  test "prefers json object from reasoning content" do
    response = {
      "choices" => [
        {
          "message" => {
            "content" => "",
            "reasoning_content" => <<~REASONING
              ```json
              {"positive":"1girl","negative":"blurry"}
              ```
            REASONING
          }
        }
      ]
    }

    assert_equal '{"positive":"1girl","negative":"blurry"}', LlamaCppClient.message_text(response)
  end

  test "prefers parseable json in reasoning over truncated content" do
    response = {
      "choices" => [
        {
          "message" => {
            "content" => '{"style_id":"watercolor_human_silhouette","subject_prompt":"silhouette","negative_extra":"photorealistic, 3d, anime, detailed face',
            "reasoning_content" => '{"style_id":"watercolor_human_silhouette","subject_prompt":"silhouette","negative_extra":"photorealistic, 3d","aspect_ratio":"square"}'
          }
        }
      ]
    }

    parsed = JSON.parse(LlamaCppClient.message_text(response))

    assert_equal "square", parsed["aspect_ratio"]
    assert_equal "photorealistic, 3d", parsed["negative_extra"]
  end

  test "extracts text from array content" do
    response = {
      "choices" => [
        {
          "message" => {
            "content" => [
              { "type" => "text", "text" => "猫が写っています" }
            ]
          }
        }
      ]
    }

    assert_equal "猫が写っています", LlamaCppClient.message_text(response)
  end

  test "stores api token for authenticated backends" do
    client = LlamaCppClient.new(base_url: "http://llama.test:8080", api_token: "sk-test")

    assert_equal "sk-test", client.instance_variable_get(:@api_token)
  end

  test "enables ssl for https base urls" do
    ssl_enabled = nil
    response = Struct.new(:body).new('{"choices":[{"message":{"content":"{}"}}]}')
    def response.is_a?(klass)
      klass == Net::HTTPSuccess
    end

    fake_http = Object.new
    fake_http.define_singleton_method(:open_timeout=) { |_| }
    fake_http.define_singleton_method(:read_timeout=) { |_| }
    fake_http.define_singleton_method(:use_ssl=) { |value| ssl_enabled = value }
    fake_http.define_singleton_method(:request) { |_| response }

    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*| fake_http }

    LlamaCppClient.new(base_url: "https://api.openai.com", api_token: "sk-test").chat(
      messages: [{ role: "user", content: "hi" }]
    )

    assert_equal true, ssl_enabled
  ensure
    Net::HTTP.define_singleton_method(:new, original_new)
  end
end
