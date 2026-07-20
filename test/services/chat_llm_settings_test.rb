# frozen_string_literal: true

require "test_helper"

class ChatLlmSettingsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    LlmSamplingPresetSeeds.seed!
  end

  test "blank values are omitted from stored hash" do
    settings = ChatLlmSettings.normalize(
      "temperature" => "",
      "top_p" => " ",
      "max_tokens" => nil
    )

    assert_equal({}, settings)
  end

  test "clamps and stores provided values" do
    settings = ChatLlmSettings.normalize(
      "temperature" => "1.5",
      "top_p" => "0.9",
      "max_tokens" => "4096",
      "top_k" => "40",
      "repeat_penalty" => "1.1",
      "min_p" => "0.05"
    )

    assert_equal 1.5, settings["temperature"]
    assert_in_delta 0.9, settings["top_p"]
    assert_equal 4096, settings["max_tokens"]
    assert_equal 40, settings["top_k"]
    assert_in_delta 1.1, settings["repeat_penalty"]
    assert_in_delta 0.05, settings["min_p"]
  end

  test "apply sets temperature and merges request params with existing params" do
    llm_chat = RubyLLM.chat(model: "gpt-oss", provider: :openai, assume_model_exists: true)
    llm_chat.with_params(cache_prompt: true, id_slot: 2)

    ChatLlmSettings.from(
      "temperature" => "0.7",
      "top_p" => "0.95",
      "top_k" => "30",
      "reasoning_effort" => "medium"
    ).apply!(llm_chat)

    assert_in_delta 0.7, llm_chat.instance_variable_get(:@temperature)
    assert_equal(
      { cache_prompt: true, id_slot: 2, top_p: 0.95, top_k: 30, reasoning_effort: "medium" },
      llm_chat.instance_variable_get(:@params)
    )
  end

  test "apply! falls back to AppSetting default when chat llm_params blank" do
    AppSetting.delete_all
    AppSetting.instance.update!(default_llm_sampling_preset_key: "qwen3_5_9b")
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"), llm_params: {})

    llm_chat = RubyLLM.chat(model: "gpt-oss", provider: :openai, assume_model_exists: true)
    ChatLlmSettings.apply!(llm_chat, chat: chat)

    assert_in_delta 0.7, llm_chat.instance_variable_get(:@temperature)
    assert_in_delta 0.8, llm_chat.instance_variable_get(:@params)[:top_p]
  end

  test "apply! prefers chat llm_params over defaults for overlapping keys" do
    AppSetting.delete_all
    AppSetting.instance.update!(default_llm_sampling_preset_key: "qwen3_5_9b")
    chat = Chat.create!(
      model: Model.find_by!(provider: "openai", model_id: "gpt-oss"),
      llm_params: { "temperature" => 0.2 }
    )

    llm_chat = RubyLLM.chat(model: "gpt-oss", provider: :openai, assume_model_exists: true)
    ChatLlmSettings.apply!(llm_chat, chat: chat)

    assert_in_delta 0.2, llm_chat.instance_variable_get(:@temperature)
    assert_in_delta 0.8, llm_chat.instance_variable_get(:@params)[:top_p]
  end

  test "connection profile sampling overlays app default for the model" do
    AppSetting.delete_all
    AppSetting.instance.update!(default_llm_sampling_preset_key: "qwen3_5_9b")

    connection = ServiceConnection.find_by!(key: "gpt_oss")
    connection.assign_prompt_conversion_settings(
      connection.prompt_conversion_settings.to_settings_h.merge(
        "max_tokens" => 4096,
        "temperature" => 0.4
      )
    )
    connection.save!

    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    assert_equal "gpt_oss", model.metadata["connection_key"]

    defaults = ChatLlmSettings.defaults_for(model: model)
    assert_equal 4096, defaults.max_tokens
    assert_in_delta 0.4, defaults.temperature

    chat = Chat.create!(model: model, llm_params: {})
    effective = ChatLlmSettings.effective_for(chat)
    assert_equal 4096, effective.max_tokens
    assert_in_delta 0.4, effective.temperature
  end

  test "chat llm_params override connection profile values" do
    connection = ServiceConnection.find_by!(key: "gpt_oss")
    connection.assign_prompt_conversion_settings(
      connection.prompt_conversion_settings.to_settings_h.merge("max_tokens" => 1024)
    )
    connection.save!

    chat = Chat.create!(
      model: Model.find_by!(provider: "openai", model_id: "gpt-oss"),
      llm_params: { "max_tokens" => 8192 }
    )

    assert_equal 8192, ChatLlmSettings.effective_for(chat).max_tokens
  end
end
