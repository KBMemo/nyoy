# frozen_string_literal: true

require "test_helper"

class AgentGraphRunLauncherTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "creates an agent run and executes the graph" do
    run = AgentGraph::RunLauncher.call(
      chat: @chat,
      graph: launch_graph,
      state: { "input" => "start" }
    )

    assert run.completed?, -> { run.error_message }
    assert_equal "test_launch", run.graph_name
    assert_nil run.current_node
    assert_equal "start", run.state["input"]
    assert_equal true, run.state["launched"]
    assert_equal [ "start" ], run.agent_node_runs.order(:id).pluck(:node_name)
  end

  test "supersedes pending runs for the same graph before launching" do
    pending = AgentRun.create!(
      chat: @chat,
      graph_name: "test_launch",
      status: "awaiting_approval",
      current_node: "await_approval",
      state: { "approval" => "pending" }
    )

    AgentGraph::RunLauncher.call(
      chat: @chat,
      graph: launch_graph,
      state: {},
      supersede_reason: "newer test run"
    )

    assert_equal "cancelled", pending.reload.status
    assert_equal "newer test run", pending.error_message
  end

  test "for_graph launches through the registry" do
    with_registry_graph(launch_graph, supersede_reason: "newer registry run") do
      pending = AgentRun.create!(
        chat: @chat,
        graph_name: "test_launch",
        status: "awaiting_approval",
        current_node: "await_approval",
        state: { "approval" => "pending" }
      )

      run = AgentGraph::RunLauncher.for_graph(
        chat: @chat,
        graph_name: "test_launch",
        state: { "input" => "registry" }
      )

      assert run.completed?, -> { run.error_message }
      assert_equal "test_launch", run.graph_name
      assert_equal true, run.state["launched"]
      assert_equal "cancelled", pending.reload.status
      assert_equal "newer registry run", pending.error_message
    end
  end

  private

  def with_registry_graph(graph, supersede_reason:)
    singleton = class << AgentGraph::Registry; self; end
    original_graph_for = AgentGraph::Registry.method(:graph_for)
    original_supersede_reason_for = AgentGraph::Registry.method(:supersede_reason_for)

    singleton.define_method(:graph_for) { |graph_name| graph }
    singleton.define_method(:supersede_reason_for) { |graph_name| supersede_reason }
    yield
  ensure
    singleton.define_method(:graph_for) { |graph_name| original_graph_for.call(graph_name) }
    singleton.define_method(:supersede_reason_for) { |graph_name| original_supersede_reason_for.call(graph_name) }
  end

  def launch_graph
    AgentGraph::GraphDefinition.new(
      name: "test_launch",
      start_node: "start",
      nodes: { "start" => LaunchNode.new },
      edges: { "start" => AgentGraph::Edge.end }
    )
  end

  class LaunchNode
    def call(state:, run:, chat:)
      AgentGraph::NodeResult.end(updates: { "launched" => true })
    end
  end
end
