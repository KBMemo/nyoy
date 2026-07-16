# frozen_string_literal: true

require "test_helper"

class McpToolBridgeTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    NyoyConnectionStore.clear_cache!
    ChatTools::Registry.reset_client!
  end

  teardown do
    ChatTools::Registry.reset_client!
  end

  test "builds MCP tools for each available chat tool" do
    web_budget = ChatTools::WebToolBudget.from_settings
    server_context = {
      web_budget: web_budget,
      tool_instances: Mcp::ToolBridge.instances(web_budget: web_budget).index_by(&:name)
    }

    tools = Mcp::ToolBridge.mcp_tools(server_context: server_context)
    names = tools.map(&:name_value)

    assert_includes names, "fetch_url"
    assert_includes names, "create_memo"
    assert_includes names, "update_memo"
    assert_includes names, "apply_sampling_preset"
    chat_tool_names = ChatTools::Registry.tool_classes(scope: :mcp).map { |klass| klass.new.name }
    assert chat_tool_names.all? { |name| names.include?(name) }
  end

  test "maps ruby_llm params schema to MCP input schema" do
    instance = ChatTools::SearchMemos.new
    schema = Mcp::ToolBridge.input_schema_for(instance)

    assert_equal "object", schema[:type]
    assert schema[:properties].key?("q")
    assert_includes schema[:required], "q"
  end

  test "marks search tools as read only" do
    annotations = Mcp::ToolBridge.annotations_for("search_memos")

    assert annotations[:read_only_hint]
    assert_not annotations[:destructive_hint]
  end

  test "marks setting mutation tools as destructive" do
    annotations = Mcp::ToolBridge.annotations_for("apply_sampling_preset")

    assert_not annotations[:read_only_hint]
    assert annotations[:destructive_hint]
  end
end
