# frozen_string_literal: true

require "test_helper"

class AgentGraphMcpRunRequestTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
  end

  test "resolve trims required content and creates mcp chat" do
    chat, content = AgentGraph::McpRunRequest.resolve(
      chat_id: nil,
      user_content: "  調べて  ",
      required_name: "question"
    )

    assert_equal "調べて", content
    assert chat.persisted?
    assert_equal "調べて", chat.messages.where(role: :user).last.content
  end

  test "required_string rejects blank content" do
    error = assert_raises(ArgumentError) do
      AgentGraph::McpRunRequest.required_string("  ", name: "memo_ref")
    end

    assert_equal "memo_ref required", error.message
  end
end
