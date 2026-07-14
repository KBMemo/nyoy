# frozen_string_literal: true

require "test_helper"

class McpMemoWriteGraphToolsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
  end

  test "catalog includes memo write graph tools" do
    tools = Mcp::ToolCatalog.tools(server_context: {
      web_budget: ChatTools::WebToolBudget.from_settings,
      tool_instances: {}
    })
    names = tools.map(&:name_value)

    assert_includes names, "run_memo_write_graph"
    assert_includes names, "get_memo_write_graph"
    assert_includes names, "resume_memo_write_graph"
  end

  test "run_memo_write_graph auto_approve creates memo" do
    stub_create_memo(uid: "01MCPMEMO") do
      response = Mcp::MemoWriteGraphTools.run_memo_write_graph_tool.call(
        instruction: "これを徒然に保存して",
        body: "# MCP 原稿\n\n本文です",
        title: "MCP 原稿"
      )
      payload = JSON.parse(response.content.first[:text])

      assert payload["agent_run_id"].present?
      assert_equal "completed", payload["status"]
      assert_equal "01MCPMEMO", payload["memo_uid"]
      assert payload["final_answer"].present?
      refute payload["awaiting_approval"]
    end
  end

  test "run without auto_approve awaits then resumes" do
    stub_create_memo(uid: "01MCPWAIT") do
      response = Mcp::MemoWriteGraphTools.run_memo_write_graph_tool.call(
        instruction: "メモにして",
        body: "待機テスト本文",
        auto_approve: false
      )
      payload = JSON.parse(response.content.first[:text])

      assert_equal "awaiting_approval", payload["status"]
      assert payload["draft"].present?
      assert payload["note"].present?

      resume = Mcp::MemoWriteGraphTools.resume_memo_write_graph_tool.call(
        agent_run_id: payload["agent_run_id"],
        decision: "approved"
      )
      done = JSON.parse(resume.content.first[:text])

      assert_equal "completed", done["status"]
      assert_equal "01MCPWAIT", done["memo_uid"]
    end
  end

  test "get_memo_write_graph errors for missing id" do
    response = Mcp::MemoWriteGraphTools.get_memo_write_graph_tool.call(agent_run_id: 0)

    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert payload["error"].present?
  end

  private

  def stub_create_memo(uid:)
    original = ChatTools::CreateMemo.instance_method(:execute)
    ChatTools::CreateMemo.define_method(:execute) do |body:, title: nil, tags: nil|
      { "uid" => uid, "title" => title, "body" => body, "updated_at" => Time.current.iso8601 }
    end
    yield
  ensure
    ChatTools::CreateMemo.define_method(:execute, original)
  end
end
