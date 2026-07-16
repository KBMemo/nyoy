# frozen_string_literal: true

require "test_helper"

class ChatToolsRegistryTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    NyoyConnectionStore.clear_cache!
    ChatTools::Registry.reset_client!
  end

  teardown do
    ChatTools::Registry.reset_client!
  end

  test "main llm uses read only tools by default" do
    names = ChatTools::Registry.tool_classes.map { |klass| klass.new.name }

    assert_includes names, "recall_memos"
    assert_includes names, "web_search"
    assert_includes names, "fetch_url"
    assert_includes names, "list_sampling_presets"
    assert_not_includes names, "create_memo"
    assert_not_includes names, "update_memo"
    assert_not_includes names, "apply_sampling_preset"
  end

  test "main llm tool mode can allow all available tools" do
    original_mode = Rails.application.config.x.nyoy.main_llm_tool_mode
    Rails.application.config.x.nyoy.main_llm_tool_mode = "all"

    names = ChatTools::Registry.tool_classes.map { |klass| klass.new.name }

    assert_includes names, "create_memo"
    assert_includes names, "update_memo"
    assert_includes names, "apply_sampling_preset"
  ensure
    Rails.application.config.x.nyoy.main_llm_tool_mode = original_mode
  end

  test "main llm tool allowlist overrides mode" do
    original_mode = Rails.application.config.x.nyoy.main_llm_tool_mode
    original_allowlist = Rails.application.config.x.nyoy.main_llm_tool_allowlist
    Rails.application.config.x.nyoy.main_llm_tool_mode = "all"
    Rails.application.config.x.nyoy.main_llm_tool_allowlist = "recall_memos, fetch_url"

    names = ChatTools::Registry.tool_classes.map { |klass| klass.new.name }

    assert_equal %w[recall_memos fetch_url].sort, names.sort
  ensure
    Rails.application.config.x.nyoy.main_llm_tool_mode = original_mode
    Rails.application.config.x.nyoy.main_llm_tool_allowlist = original_allowlist
  end

  test "available when memo or web tools are configured" do
    assert ChatTools::Registry.available?
  end

  test "memo tools available when kbmemo connection has token" do
    assert ChatTools::Registry.memo_tools_available?
  end

  test "memo tools not available without token" do
    service_connections(:kbmemo).update!(api_token: nil, enabled: true)
    NyoyConnectionStore.clear_cache!

    assert_not ChatTools::Registry.memo_tools_available?
    assert ChatTools::Registry.available?
    assert_includes ChatTools::Registry.tool_classes, ChatTools::FetchUrl
  end

  test "web tools available when searfront connection is enabled" do
    assert ChatTools::Registry.web_tools_available?
    assert_includes ChatTools::Registry.tool_classes, ChatTools::WebSearch
  end

  test "web tools not available when searfront is disabled" do
    service_connections(:searfront).update!(enabled: false)
    NyoyConnectionStore.clear_cache!

    assert_not ChatTools::Registry.web_tools_available?
    assert_not_includes ChatTools::Registry.tool_classes, ChatTools::WebSearch
    assert_includes ChatTools::Registry.tool_classes, ChatTools::FetchUrl
    assert_includes ChatTools::Registry.tool_classes, ChatTools::SearchFetchedPage
  end

  test "vision tools available when vision llama is enabled" do
    assert ChatTools::Registry.vision_tools_available?
    assert_includes ChatTools::Registry.tool_classes, ChatTools::AnalyzeImage
  end

  test "vision tools not available when vision llama is disabled" do
    service_connections(:vision_llama).update!(enabled: false)
    NyoyConnectionStore.clear_cache!

    assert_not ChatTools::Registry.vision_tools_available?
    assert_not_includes ChatTools::Registry.tool_classes, ChatTools::AnalyzeImage
  end

  test "apply uses calls one to limit parallel tool calls" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    captured = {}
    llm_chat = Object.new
    llm_chat.define_singleton_method(:with_tools) do |*tools, **kwargs|
      captured[:tools] = tools
      captured[:calls] = kwargs[:calls]
      captured[:concurrency] = kwargs[:concurrency]
      llm_chat
    end
    llm_chat.define_singleton_method(:with_instructions) { |*, **| llm_chat }

    ChatTools::Registry.apply!(llm_chat, chat: chat)

    assert captured[:tools].present?
    assert_equal :one, captured[:calls]
    assert_equal false, captured[:concurrency]
  end

  test "apply registers analyze_image for chat with attachments context" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    instances = ChatTools::Registry.tool_instances(chat)
    tool_names = instances.map { |tool| tool.name }

    assert_includes tool_names, "analyze_image"
    assert_includes tool_names, "search_fetched_page"
    assert_includes tool_names, "list_albums"
    assert_includes tool_names, "get_media"
  end

  test "web tools share a budget within one tool_instances call" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    instances = ChatTools::Registry.tool_instances(chat)
    web_search = instances.find { |tool| tool.name == "web_search" }
    fetch_url = instances.find { |tool| tool.name == "fetch_url" }
    budget = web_search.instance_variable_get(:@budget)

    assert_same budget, fetch_url.instance_variable_get(:@budget)
    assert_equal 2, budget.max_searches
    assert_equal 3, budget.max_fetches
  end

  test "web tool budget reads limits from searfront connection settings" do
    service_connections(:searfront).update!(
      settings: service_connections(:searfront).settings.merge(
        "max_searches_per_turn" => 1,
        "max_fetches_per_turn" => 4
      )
    )
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    budget = ChatTools::Registry.tool_instances(chat).find { |tool| tool.name == "web_search" }
      .instance_variable_get(:@budget)

    assert_equal 1, budget.max_searches
    assert_equal 4, budget.max_fetches
  end

  test "media tools not available without token" do
    service_connections(:tsuzura).update!(api_token: nil, enabled: true)
    NyoyConnectionStore.clear_cache!

    assert_not ChatTools::Registry.media_tools_available?
    assert_not_includes ChatTools::Registry.tool_classes, ChatTools::ListAlbums
  end

  test "sampling tools are always available" do
    assert_includes ChatTools::Registry.tool_classes, ChatTools::ListSamplingPresets
    assert_includes ChatTools::Registry.tool_classes(scope: :mcp), ChatTools::ApplySamplingPreset
  end

  test "search_memos returns memos from client" do
    fake_client = Object.new
    calls = []
    fake_client.define_singleton_method(:list_memos) do |**kwargs|
      calls << kwargs
      { "memos" => [{ "uid" => "01J8X2K3M4N5P6Q7R8S9T0UVWX", "title" => "旅行" }] }
    end
    original_client = ChatTools::Registry.method(:client)
    ChatTools::Registry.define_singleton_method(:client) { fake_client }

    result = ChatTools::SearchMemos.new.execute(q: "旅行")

    assert_equal 1, result[:memos].size
    assert_equal "旅行", calls.first[:q]
    assert_equal 10, calls.first[:limit]
  ensure
    ChatTools::Registry.define_singleton_method(:client, original_client) if defined?(original_client)
  end

  test "recall_memos registered in tool mode and absent in inject mode" do
    original_mode = Rails.application.config.x.nyoy.memo_rag_mode

    Rails.application.config.x.nyoy.memo_rag_mode = "tool"
    assert_includes ChatTools::Registry.tool_classes, ChatTools::RecallMemos

    Rails.application.config.x.nyoy.memo_rag_mode = "inject"
    assert_not_includes ChatTools::Registry.tool_classes, ChatTools::RecallMemos
  ensure
    Rails.application.config.x.nyoy.memo_rag_mode = original_mode
  end

  test "recall_memos returns formatted context from the rag pipeline" do
    original = ChatMemoRagInjector.method(:context_for)
    ChatMemoRagInjector.define_singleton_method(:context_for) { |**| "徒然メモの抜粋: 清水寺" }

    result = ChatTools::RecallMemos.new.execute(query: "京都の観光")

    assert_equal "徒然メモの抜粋: 清水寺", result[:context]
  ensure
    ChatMemoRagInjector.define_singleton_method(:context_for, original) if defined?(original)
  end

  test "recall_memos reports when nothing relevant is found" do
    original = ChatMemoRagInjector.method(:context_for)
    ChatMemoRagInjector.define_singleton_method(:context_for) { |**| nil }

    result = ChatTools::RecallMemos.new.execute(query: "無関係")

    assert_nil result[:context]
    assert result[:note].present?
  ensure
    ChatMemoRagInjector.define_singleton_method(:context_for, original) if defined?(original)
  end

  test "update_memo rejects body and append_body together" do
    result = ChatTools::UpdateMemo.new.execute(
      memo_ref: "42",
      updated_at: "2026-06-20T14:30:00Z",
      body: "new",
      append_body: "more"
    )

    assert_equal "body と append_body は同時に指定できません", result[:error]
  end
end
