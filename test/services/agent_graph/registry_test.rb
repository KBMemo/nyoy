# frozen_string_literal: true

require "test_helper"

class AgentGraphRegistryTest < ActiveSupport::TestCase
  teardown do
    AgentGraph::Registry.reset!
  end

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

  test "rejects graph classes registered under mismatched names" do
    AgentGraph::Registry.reset!
    AgentGraph::Registry.register(
      key: "registered_graph",
      graph: MismatchedGraph,
      runner: AgentGraph::ResearchGraphRunner,
      summary: AgentGraph::ResearchRunSummary
    )

    error = assert_raises(ArgumentError) do
      AgentGraph::Registry.graph_for("registered_graph")
    end

    assert_equal "registered graph name mismatch: registered_graph != actual_graph", error.message
  end

  test "registers custom graph entries through public API" do
    AgentGraph::Registry.reset!
    entry = AgentGraph::Registry.register(
      key: "custom_graph",
      graph: CustomGraph,
      runner: AgentGraph::ResearchGraphRunner,
      summary: AgentGraph::ResearchRunSummary,
      failure_label: "Custom Graph failed",
      supersede_reason: "superseded by a newer custom run"
    )

    assert_equal "custom_graph", entry.graph_name
    assert_instance_of CustomGraph, AgentGraph::Registry.graph_for("custom_graph")
    assert_equal AgentGraph::ResearchGraphRunner, AgentGraph::Registry.runner_for("custom_graph")
    assert_equal AgentGraph::ResearchRunSummary, AgentGraph::Registry.summary_for("custom_graph")
    assert_equal "Custom Graph failed", AgentGraph::Registry.failure_label_for("custom_graph")
    assert_equal "superseded by a newer custom run", AgentGraph::Registry.supersede_reason_for("custom_graph")
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

  test "returns approval copy only for approval graphs" do
    memo_write = AgentGraph::Registry.approval_copy_for("memo_write")
    memo_update = AgentGraph::Registry.approval_copy_for("memo_update")

    assert_equal "MemoWrite", memo_write.status_label
    assert_equal "内容を確認してから徒然に新規保存してください。", memo_write.description
    assert_equal "この内容で徒然に保存する", memo_write.approve_label
    assert_equal "このメモ保存を却下しますか？", memo_write.reject_confirm
    assert_equal "MemoUpdate", memo_update.status_label
    assert_equal "内容を確認してから既存メモへ反映してください。", memo_update.description
    assert_equal "この内容で徒然メモを更新する", memo_update.approve_label
    assert_equal "このメモ更新を却下しますか？", memo_update.reject_confirm

    error = assert_raises(ArgumentError) do
      AgentGraph::Registry.approval_copy_for("research")
    end
    assert_includes error.message, "approval copy is not supported"
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

  private

  class MismatchedGraph
    def name
      "actual_graph"
    end
  end

  class CustomGraph
    def name
      "custom_graph"
    end
  end
end
