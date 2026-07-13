# frozen_string_literal: true

require "test_helper"

class LlmSamplingPresetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    LlmSamplingPresetSeeds.seed!
  end

  test "index html" do
    get llm_sampling_presets_path

    assert_response :success
    assert_match "Qwen3.5", response.body
  end

  test "index json lists enabled presets" do
    get llm_sampling_presets_path(format: :json)

    assert_response :success
    body = response.parsed_body
    keys = body.fetch("presets").map { |preset| preset["key"] }
    assert_includes keys, "qwen3_5_9b"
  end

  test "show json" do
    preset = LlmSamplingPreset.find_by!(key: "qwen3_5_9b")

    get llm_sampling_preset_path(preset, format: :json)

    assert_response :success
    assert_equal "qwen3_5_9b", response.parsed_body["key"]
    assert_in_delta 0.7, response.parsed_body.dig("params", "temperature")
  end
end
