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

  test "update persists enable_thinking false and redisplays it" do
    preset = LlmSamplingPreset.find_by!(key: "qwen3_5_9b")
    preset.update!(params: preset.params.merge("enable_thinking" => true))

    patch llm_sampling_preset_path(preset), params: {
      llm_sampling_preset: {
        name: preset.name,
        enabled: "1",
        sort_order: preset.sort_order,
        temperature: "0.7",
        top_p: "0.8",
        top_k: "20",
        min_p: "0.0",
        presence_penalty: "0.8",
        frequency_penalty: "0.2",
        repeat_penalty: "1.08",
        max_tokens: "1024",
        enable_thinking: "false"
      }
    }

    assert_redirected_to llm_sampling_preset_path(preset)
    preset.reload
    assert_equal false, preset.params["enable_thinking"]
    assert_equal "false", preset.enable_thinking

    get edit_llm_sampling_preset_path(preset)
    assert_response :success
    assert_select "select#llm_sampling_preset_enable_thinking option[value=false][selected]"
  end
end
