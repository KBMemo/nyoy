# frozen_string_literal: true

require "test_helper"

class ChatMemoRagInjectorTest < ActiveSupport::TestCase
  test "appends memo context instructions when chunks exist" do
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
    original = ChatMemoRagInjector.method(:enabled?)
    ChatMemoRagInjector.define_singleton_method(:enabled?) { true }
    ChatMemoRagInjector.apply!(llm_chat, query: "京都の観光")
    ChatMemoRagInjector.define_singleton_method(:enabled?, original)

    system_messages = llm_chat.messages.select { |message| message.role == :system }
    assert system_messages.any? { |message| message.content.to_s.include?("徒然メモの抜粋") }
    assert system_messages.any? { |message| message.content.to_s.include?("清水寺") }
  end
end
