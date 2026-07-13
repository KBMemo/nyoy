# frozen_string_literal: true

require "test_helper"

class ChatToolsSamplingPresetsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    LlmSamplingPresetSeeds.seed!
  end

  test "list_sampling_presets returns enabled presets" do
    result = ChatTools::ListSamplingPresets.new.execute

    keys = result.fetch(:presets).map { |preset| preset["key"] }
    assert_includes keys, "qwen3_5_9b"
  end

  test "apply_sampling_preset updates chat llm_params from current chat" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    preset = LlmSamplingPreset.find_by!(key: "qwen3_5_9b")

    result = ChatTools::ApplySamplingPreset.new(chat: chat).execute(preset_key: "qwen3_5_9b")

    assert_equal chat.id, result[:chat_id]
    assert_equal "qwen3_5_9b", result[:preset_key]
    expected = ChatLlmSettings.normalize(preset.sampling_params.to_h)
    assert_equal expected, result[:llm_params]
    assert_equal expected, chat.reload.llm_params
    assert_nil chat.llm_params["enable_thinking"]
  end

  test "apply_sampling_preset requires chat_id when chat is missing" do
    result = ChatTools::ApplySamplingPreset.new.execute(preset_key: "qwen3_5_9b")

    assert_match(/chat_id/, result[:error])
  end

  test "apply_sampling_preset uses chat_id for MCP-style calls" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))

    result = ChatTools::ApplySamplingPreset.new.execute(preset_key: "qwen3_5_9b", chat_id: chat.id)

    assert_equal chat.id, result[:chat_id]
    assert_equal 0.7, chat.reload.llm_params["temperature"]
  end

  test "apply_sampling_preset returns error for unknown preset" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))

    result = ChatTools::ApplySamplingPreset.new(chat: chat).execute(preset_key: "missing_key")

    assert_match(/見つかりません/, result[:error])
  end

  test "apply_sampling_preset returns error for unknown chat_id" do
    result = ChatTools::ApplySamplingPreset.new.execute(preset_key: "qwen3_5_9b", chat_id: 0)

    assert_match(/チャットが見つかりません/, result[:error])
  end
end
