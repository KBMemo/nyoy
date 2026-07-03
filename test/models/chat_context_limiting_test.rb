# frozen_string_literal: true

require "test_helper"

class ChatContextLimitingIntegrationTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @original_turns = Rails.application.config.x.nyoy.chat_context_turns
    Rails.application.config.x.nyoy.chat_context_turns = 1
  end

  teardown do
    Rails.application.config.x.nyoy.chat_context_turns = @original_turns
  end

  test "to_llm loads only the latest turn plus system messages" do
    @chat.messages.create!(role: :system, content: "system note")
    @chat.messages.create!(role: :user, content: "old question")
    @chat.messages.create!(role: :assistant, content: "old answer")
    @chat.messages.create!(role: :user, content: "new question")
    @chat.messages.create!(role: :assistant, content: "new answer")

    original_apply = ChatTools::Registry.method(:apply!)
    original_rag = ChatMemoRagInjector.method(:apply!)
    ChatTools::Registry.define_singleton_method(:apply!) { |llm_chat, **| llm_chat }
    ChatMemoRagInjector.define_singleton_method(:apply!) { |chat, **| chat }
    llm = @chat.to_llm
    contents = llm.messages.map(&:content)

    assert_not_includes contents, "old question"
    assert_not_includes contents, "old answer"
    assert_includes contents, "system note"
    assert_includes contents, "new question"
    assert_includes contents, "new answer"
    assert llm.messages.any? { |message| message.role == :system && message.content.to_s.include?("以前の会話の要約") }
  ensure
    ChatTools::Registry.define_singleton_method(:apply!, original_apply) if defined?(original_apply)
    ChatMemoRagInjector.define_singleton_method(:apply!, original_rag) if defined?(original_rag)
  end
end
