# frozen_string_literal: true

require "test_helper"

class ChatLlmSettingsTest < ActiveSupport::TestCase
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
      "top_k" => "30"
    ).apply!(llm_chat)

    assert_in_delta 0.7, llm_chat.instance_variable_get(:@temperature)
    assert_equal(
      { cache_prompt: true, id_slot: 2, top_p: 0.95, top_k: 30 },
      llm_chat.instance_variable_get(:@params)
    )
  end
end
