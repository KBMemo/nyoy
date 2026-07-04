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
    assert_includes contents, "new answer"
    latest_user = llm.messages.reverse.find { |message| message.role == :user }
    assert_not_nil latest_user
    assert_includes latest_user.content.to_s, "new question"
    assert_includes latest_user.content.to_s, "以前の会話の要約"
    assert llm.messages.none? { |message| message.role == :system && message.content.to_s.include?("以前の会話の要約") }
  ensure
    ChatTools::Registry.define_singleton_method(:apply!, original_apply) if defined?(original_apply)
    ChatMemoRagInjector.define_singleton_method(:apply!, original_rag) if defined?(original_rag)
  end

  test "to_llm enables llama prompt cache with sticky slot" do
    @chat.messages.create!(role: :user, content: "hello")
    original_slots = Rails.application.config.x.nyoy.llama_slot_count
    original_cache = Rails.application.config.x.nyoy.llama_cache_prompt
    original_llama_new = LlamaCppClient.method(:new)
    Rails.application.config.x.nyoy.llama_slot_count = 0
    Rails.application.config.x.nyoy.llama_cache_prompt = true
    ChatLlamaCache.clear_props_cache!

    client = Object.new
    client.define_singleton_method(:total_slots) { 4 }
    LlamaCppClient.define_singleton_method(:new) { |**| client }

    original_apply = ChatTools::Registry.method(:apply!)
    original_rag = ChatMemoRagInjector.method(:apply!)
    ChatTools::Registry.define_singleton_method(:apply!) { |llm_chat, **| llm_chat }
    ChatMemoRagInjector.define_singleton_method(:apply!) { |chat, **| chat }

    llm = @chat.to_llm
    params = llm.instance_variable_get(:@params)

    assert_equal true, params[:cache_prompt]
    assert_equal @chat.id % 4, params[:id_slot]
  ensure
    Rails.application.config.x.nyoy.llama_slot_count = original_slots
    Rails.application.config.x.nyoy.llama_cache_prompt = original_cache
    ChatLlamaCache.clear_props_cache!
    LlamaCppClient.define_singleton_method(:new, original_llama_new) if defined?(original_llama_new)
    ChatTools::Registry.define_singleton_method(:apply!, original_apply) if defined?(original_apply)
    ChatMemoRagInjector.define_singleton_method(:apply!, original_rag) if defined?(original_rag)
  end
end
