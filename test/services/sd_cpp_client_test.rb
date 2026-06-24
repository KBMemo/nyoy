# frozen_string_literal: true

require "test_helper"

class SdCppClientTest < ActiveSupport::TestCase
  test "txt2img payload includes sampler vae tiling and lora" do
    client = SdCppClient.new(base_url: "http://example.test")
    captured = {}

    client.define_singleton_method(:post_json) do |path, payload|
      captured[:path] = path
      captured[:payload] = payload
      { "images" => [Base64.strict_encode64("png")] }
    end

    client.txt2img(
      prompt: "test",
      sampler_name: "euler_a",
      vae_tiling: true,
      lora: [{ "path" => "foo.safetensors", "multiplier" => 0.8 }]
    )

    assert_equal "/sdapi/v1/txt2img", captured[:path]
    assert_equal "euler_a", captured[:payload][:sampler_name]
    assert captured[:payload][:vae_tiling]
    assert_in_delta 0.8, captured[:payload][:loras].first["multiplier"]
  end
end
