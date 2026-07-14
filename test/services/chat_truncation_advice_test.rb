# frozen_string_literal: true

require "test_helper"

class ChatTruncationAdviceTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
  end

  test "mentions context window when max_tokens exceeds it" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    model.update!(context_window: 8192)
    chat = Chat.create!(model: model, llm_params: { "max_tokens" => 16_000 })

    message = ChatTruncationAdvice.message_for(chat)

    assert_includes message, "8192"
    assert_includes message, "--ctx-size"
    assert_includes message, "16000"
  end

  test "suggests raising max_tokens when within context window" do
    model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    model.update!(context_window: 32_768)
    chat = Chat.create!(model: model, llm_params: { "max_tokens" => 1024 })

    message = ChatTruncationAdvice.message_for(chat)

    assert_includes message, "max_tokens"
    refute_includes message, "--ctx-size"
  end
end
