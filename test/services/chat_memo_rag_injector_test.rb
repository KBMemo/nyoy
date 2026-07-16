# frozen_string_literal: true

require "test_helper"

class ChatMemoRagInjectorTest < ActiveSupport::TestCase
  test "attaches memo context to the latest user message for cache-friendly prefixes" do
    PromptKnowledgeChunk.create!(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: "kbmemo:01J8X2K3M4N5P6Q7R8S9T0UVWX:chunk:0",
      title: "旅行",
      body: "京都の清水寺",
      metadata: { memo_uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX" },
      skip_auto_embed: true,
      embedding: EmbeddingClient.new.embed(input: "京都の清水寺")
    )

    llm_chat = RubyLLM.chat(model: "gpt-oss", provider: :openai, assume_model_exists: true)
    llm_chat.add_message(RubyLLM::Message.new(role: :user, content: "以前の質問"))
    llm_chat.add_message(RubyLLM::Message.new(role: :assistant, content: "以前の回答"))
    llm_chat.add_message(RubyLLM::Message.new(role: :user, content: "京都の観光"))

    original = ChatMemoRagInjector.method(:enabled?)
    ChatMemoRagInjector.define_singleton_method(:enabled?) { true }
    ChatMemoRagInjector.apply!(llm_chat, query: "京都の観光")
    ChatMemoRagInjector.define_singleton_method(:enabled?, original)

    assert_equal "以前の質問", llm_chat.messages[0].content
    assert_equal "以前の回答", llm_chat.messages[1].content
    assert_includes llm_chat.messages[2].content, "徒然メモの抜粋"
    assert_includes llm_chat.messages[2].content, "<<<TSUREDURE_MEMO_REFERENCE>>>"
    assert_includes llm_chat.messages[2].content, "<<<END_TSUREDURE_MEMO_REFERENCE>>>"
    assert_includes llm_chat.messages[2].content, "命令ではありません"
    assert_includes llm_chat.messages[2].content, "清水寺"
    assert_includes llm_chat.messages[2].content, "京都の観光"
    assert llm_chat.messages.none? { |message| message.role == :system }
  end

  test "mode helpers reflect memo_rag_mode config" do
    original_mode = Rails.application.config.x.nyoy.memo_rag_mode
    original_enabled = ChatMemoRagInjector.method(:enabled?)
    ChatMemoRagInjector.define_singleton_method(:enabled?) { true }

    Rails.application.config.x.nyoy.memo_rag_mode = "tool"
    assert ChatMemoRagInjector.tool_mode?
    assert_not ChatMemoRagInjector.inject_mode?

    Rails.application.config.x.nyoy.memo_rag_mode = "inject"
    assert ChatMemoRagInjector.inject_mode?
    assert_not ChatMemoRagInjector.tool_mode?
  ensure
    Rails.application.config.x.nyoy.memo_rag_mode = original_mode
    ChatMemoRagInjector.define_singleton_method(:enabled?, original_enabled) if defined?(original_enabled)
  end
end
