# frozen_string_literal: true

require "test_helper"

class AgentGraphRegistryTest < ActiveSupport::TestCase
  test "returns runners for known graphs" do
    assert_equal AgentGraph::ResearchGraphRunner, AgentGraph::Registry.runner_for("research")
    assert_equal AgentGraph::MemoWriteGraphRunner, AgentGraph::Registry.runner_for("memo_write")
    assert_equal AgentGraph::MemoUpdateGraphRunner, AgentGraph::Registry.runner_for("memo_update")
  end

  test "builds graph definitions for known graphs" do
    assert_instance_of AgentGraph::ResearchGraph, AgentGraph::Registry.graph_for("research")
    assert_instance_of AgentGraph::MemoWriteGraph, AgentGraph::Registry.graph_for("memo_write")
    assert_instance_of AgentGraph::MemoUpdateGraph, AgentGraph::Registry.graph_for("memo_update")
  end

  test "returns supersede reasons for known graphs" do
    assert_equal "superseded by a newer research run", AgentGraph::Registry.supersede_reason_for("research")
    assert_equal "superseded by a newer memo write run", AgentGraph::Registry.supersede_reason_for("memo_write")
    assert_equal "superseded by a newer memo update run", AgentGraph::Registry.supersede_reason_for("memo_update")
  end

  test "returns summary classes for known graphs" do
    assert_equal AgentGraph::ResearchRunSummary, AgentGraph::Registry.summary_for("research")
    assert_equal AgentGraph::MemoWriteRunSummary, AgentGraph::Registry.summary_for("memo_write")
    assert_equal AgentGraph::MemoUpdateRunSummary, AgentGraph::Registry.summary_for("memo_update")
  end

  test "returns mcp resume tools for approval graphs" do
    assert_nil AgentGraph::Registry.resume_tool_for("research")
    assert_equal "resume_memo_write_graph", AgentGraph::Registry.resume_tool_for("memo_write")
    assert_equal "resume_memo_update_graph", AgentGraph::Registry.resume_tool_for("memo_update")
  end

  test "tracks approval capable graphs" do
    assert_equal %w[memo_write memo_update], AgentGraph::Registry.approval_graph_names
    assert AgentGraph::Registry.approval_supported?("memo_write")
    assert AgentGraph::Registry.approval_supported?("memo_update")
    assert_not AgentGraph::Registry.approval_supported?("research")
  end

  test "returns approval panel only for approval graphs" do
    assert_equal "chats/memo_write_approval", AgentGraph::Registry.approval_panel_for("memo_write")
    assert_equal "chats/memo_write_approval", AgentGraph::Registry.approval_panel_for("memo_update")

    error = assert_raises(ArgumentError) do
      AgentGraph::Registry.approval_panel_for("research")
    end
    assert_includes error.message, "approval panel is not supported"
  end

  test "returns approval notices only for approval graphs" do
    assert_equal "メモ草案を承認しました。徒然へ保存します。", AgentGraph::Registry.approve_notice_for("memo_write")
    assert_equal "メモ保存を却下しました。", AgentGraph::Registry.reject_notice_for("memo_write")
    assert_equal "メモ更新を承認しました。徒然へ反映します。", AgentGraph::Registry.approve_notice_for("memo_update")
    assert_equal "メモ更新を却下しました。", AgentGraph::Registry.reject_notice_for("memo_update")

    error = assert_raises(ArgumentError) do
      AgentGraph::Registry.approve_notice_for("research")
    end
    assert_includes error.message, "approval notice is not supported"
  end

  test "falls back failure label for unknown graph names" do
    assert_equal "MemoWrite Graph failed", AgentGraph::Registry.failure_label_for("memo_write")
    assert_equal "custom Graph failed", AgentGraph::Registry.failure_label_for("custom")
  end
end
