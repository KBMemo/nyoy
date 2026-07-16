# frozen_string_literal: true

require "test_helper"

class McpMemoUpdateGraphToolsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
  end

  test "catalog includes memo update graph tools" do
    tools = Mcp::ToolCatalog.tools(server_context: {
      web_budget: ChatTools::WebToolBudget.from_settings,
      tool_instances: {}
    })
    names = tools.map(&:name_value)

    assert_includes names, "run_memo_update_graph"
    assert_includes names, "get_memo_update_graph"
    assert_includes names, "resume_memo_update_graph"
  end

  test "run_memo_update_graph auto_approve updates memo" do
    stub_get_memo do
      stub_update_memo(uid: "01UPDATED") do
        response = Mcp::MemoUpdateGraphTools.run_memo_update_graph_tool.call(
          instruction: "追記して",
          memo_ref: "01TARGET",
          body: "追記本文"
        )
        payload = JSON.parse(response.content.first[:text])

        assert payload["agent_run_id"].present?
        assert_equal "completed", payload["status"]
        assert_equal "01UPDATED", payload["memo_uid"]
        assert_equal "01TARGET", payload["memo_ref"]
        refute payload["awaiting_approval"]
      end
    end
  end

  test "run without auto_approve awaits then resumes" do
    stub_get_memo do
      stub_update_memo(uid: "01WAIT") do
        response = Mcp::MemoUpdateGraphTools.run_memo_update_graph_tool.call(
          instruction: "更新して",
          memo_ref: "01TARGET",
          body: "置換本文",
          mode: "replace",
          auto_approve: false
        )
        payload = JSON.parse(response.content.first[:text])

        assert_equal "awaiting_approval", payload["status"]
        assert payload["draft"].present?
        assert payload["note"].present?

        resume = Mcp::MemoUpdateGraphTools.resume_memo_update_graph_tool.call(
          agent_run_id: payload["agent_run_id"],
          decision: "approved"
        )
        done = JSON.parse(resume.content.first[:text])

        assert_equal "completed", done["status"]
        assert_equal "01WAIT", done["memo_uid"]
      end
    end
  end

  test "get_memo_update_graph errors for missing id" do
    response = Mcp::MemoUpdateGraphTools.get_memo_update_graph_tool.call(agent_run_id: 0)

    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert payload["error"].present?
  end

  private

  def stub_get_memo
    original = ChatTools::GetMemo.instance_method(:execute)
    ChatTools::GetMemo.define_method(:execute) do |memo_ref:|
      {
        "uid" => memo_ref,
        "title" => "既存メモ",
        "body" => "既存本文",
        "updated_at" => "2026-07-16T00:00:00Z"
      }
    end
    yield
  ensure
    ChatTools::GetMemo.define_method(:execute, original)
  end

  def stub_update_memo(uid:)
    original = ChatTools::UpdateMemo.instance_method(:execute)
    ChatTools::UpdateMemo.define_method(:execute) do |**|
      { "uid" => uid, "title" => "既存メモ", "updated_at" => Time.current.iso8601 }
    end
    yield
  ensure
    ChatTools::UpdateMemo.define_method(:execute, original)
  end
end
