# frozen_string_literal: true

require "test_helper"

class LlmSamplingPresetTest < ActiveSupport::TestCase
  setup do
    LlmSamplingPresetSeeds.seed!
  end

  test "enable_thinking reads boolean false from params" do
    preset = LlmSamplingPreset.find_by!(key: "qwen3_5_9b")

    assert_equal false, preset.params["enable_thinking"]
    assert_equal "false", preset.enable_thinking
  end

  test "enable_thinking reads boolean true" do
    preset = LlmSamplingPreset.create!(
      key: "thinking_on",
      name: "Thinking on",
      builtin: false,
      enabled: true,
      params: { "temperature" => 0.5, "enable_thinking" => true }
    )

    assert_equal "true", preset.enable_thinking
  end

  test "enable_thinking reads unset" do
    preset = LlmSamplingPreset.create!(
      key: "thinking_unset",
      name: "Thinking unset",
      builtin: false,
      enabled: true,
      params: { "temperature" => 0.5, "enable_thinking" => "unset" }
    )

    assert_equal "unset", preset.enable_thinking
  end

  test "enable_thinking is nil when key missing" do
    preset = LlmSamplingPreset.create!(
      key: "thinking_blank",
      name: "Thinking blank",
      builtin: false,
      enabled: true,
      params: { "temperature" => 0.5 }
    )

    assert_nil preset.enable_thinking
  end
end
