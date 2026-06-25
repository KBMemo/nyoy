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

  test "txt2img with batch_size returns multiple images" do
    client = SdCppClient.new(base_url: "http://example.test")

    client.define_singleton_method(:post_json) do |_path, _payload|
      { "images" => [Base64.strict_encode64("a"), Base64.strict_encode64("b")] }
    end

    images = client.txt2img(prompt: "test", batch_size: 2)

    assert_equal 2, images.size
    assert_equal "a", images.first
    assert_equal "b", images.last
  end

  test "img2img payload includes init image and denoising strength" do
    client = SdCppClient.new(base_url: "http://example.test")
    captured = {}

    client.define_singleton_method(:post_json) do |path, payload|
      captured[:path] = path
      captured[:payload] = payload
      { "images" => [Base64.strict_encode64("refined")] }
    end

    result = client.img2img(
      prompt: "test",
      init_image: "draft-bytes",
      denoising_strength: 0.35
    )

    assert_equal "/sdapi/v1/img2img", captured[:path]
    assert_equal [Base64.strict_encode64("draft-bytes")], captured[:payload][:init_images]
    assert_in_delta 0.35, captured[:payload][:denoising_strength]
    assert_equal "refined", result
  end
end
