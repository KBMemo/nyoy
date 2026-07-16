# frozen_string_literal: true

require "test_helper"

class AgentGraphRunResumerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "stores approval decision and resumes the graph" do
    run = awaiting_run

    completed = AgentGraph::RunResumer.call(
      run,
      graph: resume_graph,
      decision: "approved"
    )

    assert completed.completed?, -> { completed.error_message }
    assert_equal "approved", completed.state["approval"]
    assert_equal "approved", completed.state["seen_approval"]
    assert_equal [ "await_approval" ], completed.agent_node_runs.order(:id).pluck(:node_name)
  end

  test "for_graph resumes through the registry" do
    run = awaiting_run

    with_registry_graph(resume_graph) do
      completed = AgentGraph::RunResumer.for_graph(
        run,
        graph_name: "test_resume",
        decision: "approved"
      )

      assert completed.completed?, -> { completed.error_message }
      assert_equal "approved", completed.state["approval"]
      assert_equal "approved", completed.state["seen_approval"]
    end
  end

  test "rejects runs that are not awaiting approval" do
    run = awaiting_run
    run.update!(status: "completed")

    error = assert_raises(ArgumentError) do
      AgentGraph::RunResumer.call(run, graph: resume_graph, decision: "approved")
    end

    assert_equal "agent run must await approval", error.message
  end

  test "rejects invalid decisions" do
    error = assert_raises(ArgumentError) do
      AgentGraph::RunResumer.call(awaiting_run, graph: resume_graph, decision: "maybe")
    end

    assert_equal "decision required", error.message
  end

  private

  def awaiting_run
    AgentRun.create!(
      chat: @chat,
      graph_name: "test_resume",
      status: "awaiting_approval",
      current_node: "await_approval",
      state: { "approval" => "pending" }
    )
  end

  def with_registry_graph(graph)
    singleton = class << AgentGraph::Registry; self; end
    original_graph_for = AgentGraph::Registry.method(:graph_for)

    singleton.define_method(:graph_for) { |graph_name| graph }
    yield
  ensure
    singleton.define_method(:graph_for) { |graph_name| original_graph_for.call(graph_name) }
  end

  def resume_graph
    AgentGraph::GraphDefinition.new(
      name: "test_resume",
      start_node: "await_approval",
      nodes: { "await_approval" => ResumeNode.new },
      edges: { "await_approval" => AgentGraph::Edge.end }
    )
  end

  class ResumeNode
    def call(state:, run:, chat:)
      AgentGraph::NodeResult.end(updates: { "seen_approval" => state["approval"] })
    end
  end
end
