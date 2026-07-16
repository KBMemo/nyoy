# frozen_string_literal: true

require "test_helper"

class AgentGraphMcpChatResolverTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
  end

  test "returns existing chat when chat_id is provided" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))

    resolved = AgentGraph::McpChatResolver.resolve(
      chat_id: chat.id,
      user_content: "ignored"
    )

    assert_equal chat, resolved
    assert_equal 0, chat.messages.count
  end

  test "creates mcp chat with a user message when chat_id is omitted" do
    chat = AgentGraph::McpChatResolver.resolve(
      chat_id: nil,
      user_content: "MCP から実行"
    )

    assert chat.persisted?
    assert_equal "MCP から実行", chat.messages.where(role: :user).last.content
  end

  test "raises for missing chat id" do
    error = assert_raises(ArgumentError) do
      AgentGraph::McpChatResolver.resolve(chat_id: 0, user_content: "x")
    end

    assert_includes error.message, "chat not found"
  end
end
