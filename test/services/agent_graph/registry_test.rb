# frozen_string_literal: true

require "test_helper"

class AgentGraphRegistryTest < ActiveSupport::TestCase
  test "returns runners for known graphs" do
    assert_equal AgentGraph::ResearchGraphRunner, AgentGraph::Registry.runner_for("research")
    assert_equal AgentGraph::MemoWriteGraphRunner, AgentGraph::Registry.runner_for("memo_write")
    assert_equal AgentGraph::MemoUpdateGraphRunner, AgentGraph::Registry.runner_for("memo_update")
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

  test "falls back failure label for unknown graph names" do
    assert_equal "MemoWrite Graph failed", AgentGraph::Registry.failure_label_for("memo_write")
    assert_equal "custom Graph failed", AgentGraph::Registry.failure_label_for("custom")
  end
end
