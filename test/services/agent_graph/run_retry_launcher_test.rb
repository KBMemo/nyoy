# frozen_string_literal: true

require "test_helper"

class AgentGraphRunRetryLauncherTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "launches duplicate run from retryable checkpoint" do
    failed_run = create_failed_run(graph_name: "retry_test")
    completed = failed_run.agent_node_runs.create!(
      node_name: "prepare",
      status: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    checkpoint = failed_run.agent_checkpoints.create!(
      node_name: completed.node_name,
      state: { "input" => "kept" },
      created_at: completed.finished_at + 1.second
    )
    failed_run.agent_node_runs.create!(node_name: "retry_node", status: "failed")

    with_retry_graph do
      retry_run = AgentGraph::RunRetryLauncher.call(failed_run)

      assert retry_run.completed?, -> { retry_run.error_message }
      assert_equal "retry_test", retry_run.graph_name
      assert_equal "failed", failed_run.reload.status
      assert_nil retry_run.current_node
      assert_equal "kept", retry_run.state["input"]
      assert_equal true, retry_run.state["retried"]
      assert_equal failed_run.id, retry_run.state["retry_of_agent_run_id"]
      assert_equal checkpoint.id, retry_run.state["retry_from_checkpoint_id"]
      assert_equal "prepare", retry_run.state["retry_from_node"]
      assert_equal [ "retry_node" ], retry_run.agent_node_runs.order(:id).pluck(:node_name)
    end
  end

  test "does not launch when retry planner blocks" do
    failed_run = create_failed_run(graph_name: "retry_test")
    failed_run.agent_node_runs.create!(node_name: "prepare", status: "failed")

    with_retry_graph do
      assert_no_difference -> { AgentRun.count } do
        error = assert_raises(ArgumentError) do
          AgentGraph::RunRetryLauncher.call(failed_run)
        end
        assert_equal "成功済み checkpoint がありません", error.message
      end
    end
  end

  private

  def create_failed_run(graph_name:)
    AgentRun.create!(
      chat: @chat,
      graph_name: graph_name,
      status: "failed",
      current_node: "retry_node",
      state: { "input" => "original" },
      error_message: "failed"
    )
  end

  def with_retry_graph
    graph = retry_graph
    singleton = class << AgentGraph::Registry; self; end
    original_graph_for = AgentGraph::Registry.method(:graph_for)
    original_approval_supported = AgentGraph::Registry.method(:approval_supported?)

    singleton.define_method(:graph_for) { |_graph_name| graph }
    singleton.define_method(:approval_supported?) { |_graph_name| false }
    yield
  ensure
    singleton.define_method(:graph_for) { |graph_name| original_graph_for.call(graph_name) }
    singleton.define_method(:approval_supported?) { |graph_name| original_approval_supported.call(graph_name) }
  end

  def retry_graph
    AgentGraph::GraphDefinition.new(
      name: "retry_test",
      start_node: "prepare",
      nodes: {
        "retry_node" => RetryNode.new
      },
      edges: {
        "prepare" => AgentGraph::Edge.new(to: "retry_node"),
        "retry_node" => AgentGraph::Edge.end
      }
    )
  end

  class RetryNode
    def call(state:, run:, chat:)
      AgentGraph::NodeResult.end(updates: { "retried" => true })
    end
  end
end
