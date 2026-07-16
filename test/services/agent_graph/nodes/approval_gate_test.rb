# frozen_string_literal: true

require "test_helper"

class AgentGraphNodesApprovalGateTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: "test_graph",
      status: "running",
      current_node: "await_approval",
      state: {}
    )
    @node = AgentGraph::Nodes::ApprovalGate.new(
      approved_goto: "commit",
      rejected_message: "却下されました"
    )
  end

  test "interrupts when approval is pending" do
    result = @node.call(
      state: { "auto_approve" => false },
      run: @run,
      chat: @chat
    )

    assert result.interrupt?
    assert_equal({ "approval" => "pending" }, result.updates)
  end

  test "auto approves when configured" do
    result = @node.call(
      state: { "auto_approve" => true },
      run: @run,
      chat: @chat
    )

    assert_equal "commit", result.goto
    assert_equal({ "approval" => "approved" }, result.updates)
  end

  test "rejection publishes final answer and ends" do
    result = @node.call(
      state: { "approval" => "rejected" },
      run: @run,
      chat: @chat
    )

    assert result.finished?
    assert_equal "rejected", result.updates["approval"]
    assert_equal "却下されました", result.updates["final_answer"]
    assert result.updates["assistant_message_id"].present?
    assert_equal "却下されました", @chat.messages.where(role: :assistant).last.content
  end
end
