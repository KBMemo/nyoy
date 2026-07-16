# frozen_string_literal: true

require "test_helper"

class AgentGraphRunnerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "rejects graph mismatch before running nodes" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: "expected_graph",
      status: "pending",
      current_node: "start",
      state: {}
    )

    error = assert_raises(ArgumentError) do
      AgentGraph::Runner.new(run, graph: graph(name: "actual_graph")).call
    end

    assert_equal "agent run graph mismatch: expected_graph != actual_graph", error.message
    assert_equal "failed", run.reload.status
    assert_equal "agent run graph mismatch: expected_graph != actual_graph", run.error_message
    assert_empty run.agent_node_runs
  end

  private

  def graph(name:)
    AgentGraph::GraphDefinition.new(
      name: name,
      start_node: "start",
      nodes: { "start" => Node.new },
      edges: { "start" => AgentGraph::Edge.end }
    )
  end

  class Node
    def call(state:, run:, chat:)
      AgentGraph::NodeResult.end
    end
  end
end
