# frozen_string_literal: true

require "test_helper"

class PromptConversionSettingsTest < ActiveSupport::TestCase
  test "defaults enable_thinking off and json_schema auto" do
    settings = PromptConversionSettings.from({})

    assert_equal "auto", settings.json_schema
    assert_equal "false", settings.enable_thinking
    assert_equal false, settings.enable_thinking_flag
    assert_equal({ "enable_thinking" => false }, settings.chat_template_kwargs)
    assert_nil settings.temperature
    assert_nil settings.top_p
    assert_nil settings.max_tokens
    assert_equal 0.2, settings.resolved_temperature
    assert_equal 2048, settings.resolved_max_tokens(default: 2048)
  end

  test "reads nested prompt_conversion hash from connection settings" do
    settings = PromptConversionSettings.from(
      "prompt_conversion" => {
        "json_schema" => "off",
        "temperature" => "0.1",
        "top_p" => "0.8",
        "max_tokens" => "512",
        "enable_thinking" => "unset"
      }
    )

    assert_equal "off", settings.json_schema
    assert_in_delta 0.1, settings.temperature
    assert_in_delta 0.8, settings.top_p
    assert_equal 512, settings.max_tokens
    assert_equal "unset", settings.enable_thinking
    assert_nil settings.chat_template_kwargs
  end

  test "merge_into preserves sibling settings keys" do
    merged = PromptConversionSettings.merge_into(
      { "chat_models" => ["gpt-4o-mini"] },
      { json_schema: "on", enable_thinking: "true", temperature: 0.3, top_p: 0.9 }
    )

    assert_equal ["gpt-4o-mini"], merged["chat_models"]
    assert_equal "on", merged["prompt_conversion"]["json_schema"]
    assert_equal "true", merged["prompt_conversion"]["enable_thinking"]
    assert_in_delta 0.3, merged["prompt_conversion"]["temperature"]
    assert_in_delta 0.9, merged["prompt_conversion"]["top_p"]
  end
end
