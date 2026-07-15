# frozen_string_literal: true

require "test_helper"

class AgentGraphToolTraceRecorderTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "records tool call and tool result messages" do
    result = AgentGraph::ToolTraceRecorder.record!(
      @chat,
      name: "web_search",
      arguments: { q: "hydrangea" },
      result: { "results" => [ { "title" => "Rin", "url" => "https://example.com" } ] }
    )

    call_message = result[:call_message]
    result_message = result[:result_message]

    assert call_message.tool_call_message?
    assert_equal "messages/tool_calls", call_message.to_partial_path
    assert_equal "web_search", call_message.tool_calls_association.first.name
    assert_equal "hydrangea", call_message.tool_calls_association.first.arguments["q"]

    assert_equal "tool", result_message.role
    assert_equal "messages/tool", result_message.to_partial_path
    assert_equal "web_search", result_message.parent_tool_call.name
    assert_includes result_message.content, "example.com"
  end

  test "serializes string tool errors as-is" do
    result = AgentGraph::ToolTraceRecorder.record!(
      @chat,
      name: "fetch_url",
      arguments: { "url" => "https://example.com" },
      result: "[TOOL_ERROR]: fetch_url\nCODE: TOOL_ERROR"
    )

    assert_includes result[:result_message].content, "[TOOL_ERROR]"
  end
end
