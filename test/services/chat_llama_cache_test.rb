# frozen_string_literal: true

require "test_helper"

class ChatLlamaCacheTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @original_slots = Rails.application.config.x.nyoy.llama_slot_count
    @original_cache = Rails.application.config.x.nyoy.llama_cache_prompt
    @original_llama_new = LlamaCppClient.method(:new)
    ChatLlamaCache.clear_props_cache!
  end

  teardown do
    Rails.application.config.x.nyoy.llama_slot_count = @original_slots
    Rails.application.config.x.nyoy.llama_cache_prompt = @original_cache
    ChatLlamaCache.clear_props_cache!
    LlamaCppClient.define_singleton_method(:new, @original_llama_new)
  end

  test "reads slot count from llama props total_slots" do
    Rails.application.config.x.nyoy.llama_slot_count = 0
    stub_props_total_slots(8)

    assert_equal 8, ChatLlamaCache.slot_count_for(@chat)
    assert_equal @chat.id % 8, ChatLlamaCache.slot_id_for(@chat)
  end

  test "applies cache_prompt and id_slot from props" do
    Rails.application.config.x.nyoy.llama_slot_count = 0
    Rails.application.config.x.nyoy.llama_cache_prompt = true
    stub_props_total_slots(4)
    llm_chat = RubyLLM.chat(model: "gpt-oss", provider: :openai, assume_model_exists: true)

    ChatLlamaCache.apply!(llm_chat, chat: @chat)

    params = llm_chat.instance_variable_get(:@params)
    assert_equal true, params[:cache_prompt]
    assert_equal @chat.id % 4, params[:id_slot]
    metadata = llm_chat.instance_variable_get(:@nyoy_llama_cache_metadata)
    assert_equal true, metadata[:enabled]
    assert_equal true, metadata[:cache_prompt]
    assert_equal @chat.id % 4, metadata[:slot_id]
    assert_equal 4, metadata[:slot_count]
  end

  test "metadata reports disabled for OpenAI connection" do
    model = Model.create!(
      provider: "openai",
      model_id: "openai-cache-test",
      name: "openai-cache-test",
      family: "openai",
      capabilities: [ "chat" ],
      metadata: { "connection_key" => "openai" }
    )
    chat = Chat.create!(model: model)

    metadata = ChatLlamaCache.metadata_for(chat)

    assert_equal false, metadata[:enabled]
    assert_equal false, metadata[:cache_prompt]
    assert_nil metadata[:slot_id]
    assert_nil metadata[:slot_count]
  ensure
    chat&.destroy!
    model&.destroy!
  end

  test "metadata can use an explicit model connection" do
    model = Model.create!(
      provider: "openai",
      model_id: "explicit-llama-cache-test",
      name: "explicit-llama-cache-test",
      family: "local",
      capabilities: [ "chat" ],
      metadata: { "connection_key" => "llama_cpp" }
    )
    Rails.application.config.x.nyoy.llama_slot_count = 0
    Rails.application.config.x.nyoy.llama_cache_prompt = true
    stub_props_total_slots(6)

    metadata = ChatLlamaCache.metadata_for(@chat, model: model)

    assert_equal true, metadata[:enabled]
    assert_equal true, metadata[:cache_prompt]
    assert_equal @chat.id % 6, metadata[:slot_id]
    assert_equal 6, metadata[:slot_count]
  ensure
    model&.destroy!
  end

  test "slot key gives a stable purpose-specific slot" do
    Rails.application.config.x.nyoy.llama_slot_count = 0
    stub_props_total_slots(8)

    metadata = ChatLlamaCache.metadata_for(@chat, slot_key: "agent_graph:final:#{@chat.id}")

    assert_equal Zlib.crc32("agent_graph:final:#{@chat.id}") % 8, metadata[:slot_id]
  end

  test "falls back to LLAMA_SLOT_COUNT when props fails" do
    Rails.application.config.x.nyoy.llama_slot_count = 3
    stub_props_error

    assert_equal 3, ChatLlamaCache.slot_count_for(@chat)
    assert_equal @chat.id % 3, ChatLlamaCache.slot_id_for(@chat)
  end

  test "omits id_slot when props and fallback are unavailable" do
    Rails.application.config.x.nyoy.llama_slot_count = 0
    Rails.application.config.x.nyoy.llama_cache_prompt = true
    stub_props_error
    llm_chat = RubyLLM.chat(model: "gpt-oss", provider: :openai, assume_model_exists: true)

    ChatLlamaCache.apply!(llm_chat, chat: @chat)

    params = llm_chat.instance_variable_get(:@params)
    assert_equal true, params[:cache_prompt]
    assert_not params.key?(:id_slot)
  end

  private

  def stub_props_total_slots(count)
    client = Object.new
    client.define_singleton_method(:total_slots) { count }
    LlamaCppClient.define_singleton_method(:new) { |**| client }
  end

  def stub_props_error
    client = Object.new
    client.define_singleton_method(:total_slots) { raise LlamaCppClient::Error, "down" }
    LlamaCppClient.define_singleton_method(:new) { |**| client }
  end
end
