# frozen_string_literal: true

require "test_helper"

class AgentGraphPendingRunSupersederTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "cancels pending decision runs for one graph" do
    pending = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::MemoWriteGraph::NAME,
      status: "awaiting_approval",
      current_node: "await_approval",
      state: { "approval" => "pending" }
    )
    other_graph = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::MemoUpdateGraph::NAME,
      status: "awaiting_approval",
      current_node: "await_approval",
      state: { "approval" => "pending" }
    )

    AgentGraph::PendingRunSuperseder.call(
      chat: @chat,
      graph_name: AgentGraph::MemoWriteGraph::NAME,
      reason: "superseded"
    )

    assert_equal "cancelled", pending.reload.status
    assert_equal "superseded", pending.error_message
    assert_equal "awaiting_approval", other_graph.reload.status
  end

  test "ignores already decided awaiting approval runs" do
    approved = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::MemoWriteGraph::NAME,
      status: "awaiting_approval",
      current_node: "await_approval",
      state: { "approval" => "approved" }
    )

    AgentGraph::PendingRunSuperseder.call(
      chat: @chat,
      graph_name: AgentGraph::MemoWriteGraph::NAME,
      reason: "superseded"
    )

    assert_equal "awaiting_approval", approved.reload.status
  end
end
