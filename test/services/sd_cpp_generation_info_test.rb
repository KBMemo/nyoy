# frozen_string_literal: true

require "test_helper"

class SdCppGenerationInfoTest < ActiveSupport::TestCase
  test "parse extracts seed from info json string" do
    response = { "info" => '{"seed": 12345, "all_seeds": [12345]}' }

    result = SdCppGenerationInfo.parse(response)

    assert_equal 12345, result.seed
    assert_equal [12345], result.seeds
  end

  test "parse prefers all_seeds when present" do
    response = { "info" => { "seed" => 1, "all_seeds" => [10, 20] } }

    result = SdCppGenerationInfo.parse(response)

    assert_equal 10, result.seed
    assert_equal [10, 20], result.seeds
  end

  test "decode_response combines images and seed" do
    response = {
      "images" => [Base64.strict_encode64("png")],
      "info" => '{"seed": 42}'
    }

    result = SdCppGenerationInfo.decode_response(response)

    assert_equal ["png"], result.images
    assert_equal 42, result.seed
  end

  test "parse returns nil seed when info is missing" do
    result = SdCppGenerationInfo.parse({})

    assert_nil result.seed
    assert_empty result.seeds
  end
end
