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

  test "web tools available when searxng connection is enabled" do
    assert ChatTools::Registry.web_tools_available?
    assert_includes ChatTools::Registry.tool_classes, ChatTools::WebSearch
  end

  test "web tools not available when searxng is disabled" do
    service_connections(:searxng).update!(enabled: false)
    NyoyConnectionStore.clear_cache!

    assert_not ChatTools::Registry.web_tools_available?
    assert_not_includes ChatTools::Registry.tool_classes, ChatTools::WebSearch
    assert_includes ChatTools::Registry.tool_classes, ChatTools::FetchUrl
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

  test "apply registers analyze_image for chat with attachments context" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    instances = ChatTools::Registry.tool_instances(chat)
    tool_names = instances.map { |tool| tool.name }

    assert_includes tool_names, "analyze_image"
    assert_includes tool_names, "list_albums"
    assert_includes tool_names, "get_media"
  end

  test "media tools not available without token" do
    service_connections(:tsuzura).update!(api_token: nil, enabled: true)
    NyoyConnectionStore.clear_cache!

    assert_not ChatTools::Registry.media_tools_available?
    assert_not_includes ChatTools::Registry.tool_classes, ChatTools::ListAlbums
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
