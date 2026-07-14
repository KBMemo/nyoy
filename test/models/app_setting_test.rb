# frozen_string_literal: true

require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    AppSetting.delete_all
    @original_chat = Rails.application.config.x.nyoy.default_chat_connection_key
    @original_style = Rails.application.config.x.nyoy.style_plan_connection_key
    Rails.application.config.x.nyoy.default_chat_connection_key = "llama_cpp"
    Rails.application.config.x.nyoy.style_plan_connection_key = "llama_cpp"
  end

  teardown do
    Rails.application.config.x.nyoy.default_chat_connection_key = @original_chat
    Rails.application.config.x.nyoy.style_plan_connection_key = @original_style
    AppSetting.delete_all
  end

  test "falls back to env config when unset" do
    assert_equal "llama_cpp", AppSetting.default_chat_connection_key
    assert_equal "llama_cpp", AppSetting.default_style_plan_connection_key
  end

  test "prefers stored values when available" do
    AppSetting.instance.update!(
      default_chat_connection_key: "gpt_oss",
      default_style_plan_connection_key: "gpt_oss"
    )

    assert_equal "gpt_oss", AppSetting.default_chat_connection_key
    assert_equal "gpt_oss", AppSetting.default_style_plan_connection_key
  end

  test "rejects unknown connection keys" do
    setting = AppSetting.instance
    setting.default_chat_connection_key = "missing_backend"

    assert_not setting.valid?
    assert_includes setting.errors[:default_chat_connection_key], "は有効な接続を選んでください"
  end

  test "default_chat_llm_params resolves enabled sampling preset" do
    LlmSamplingPresetSeeds.seed!
    AppSetting.instance.update!(default_llm_sampling_preset_key: "qwen3_5_9b")

    params = AppSetting.default_chat_llm_params

    assert_in_delta 0.7, params["temperature"]
    assert_in_delta 0.8, params["top_p"]
    assert_nil params["enable_thinking"]
  end

  test "default_chat_llm_params is empty when unset" do
    assert_equal({}, AppSetting.default_chat_llm_params)
  end

  test "rejects unknown sampling preset keys" do
    setting = AppSetting.instance
    setting.default_llm_sampling_preset_key = "missing_preset"

    assert_not setting.valid?
    assert_includes setting.errors[:default_llm_sampling_preset_key], "は有効なサンプリングプリセットを選んでください"
  end
end
