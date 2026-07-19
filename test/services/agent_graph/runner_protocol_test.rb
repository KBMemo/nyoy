# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/agent_graph/core/node_result"
require_relative "../../../app/services/agent_graph/core/edge"
require_relative "../../../app/services/agent_graph/core/graph_definition"
require_relative "../../../app/services/agent_graph/core/cancelled"
require_relative "../../../app/services/agent_graph/core/context_protocol"
require_relative "../../../app/services/agent_graph/core/runner"
require_relative "../../../app/services/agent_graph/node_result"
require_relative "../../../app/services/agent_graph/cancelled"
require_relative "../../../app/services/agent_graph/runner"

class AgentGraphRunnerProtocolTest < Minitest::Test
  def test_runs_with_an_in_memory_context_and_state_only_nodes
    context = InMemoryContext.new(
      current_node: "prepare",
      state: { "nested" => { "input" => "original" } }
    )
    graph = AgentGraph::Core::GraphDefinition.new(
      name: "protocol_test",
      start_node: "prepare",
      nodes: {
        "prepare" => PrepareNode.new,
        "finish" => FinishNode.new
      },
      edges: {
        "prepare" => AgentGraph::Core::Edge.new(to: "finish"),
        "finish" => AgentGraph::Core::Edge.end
      }
    )

    result = AgentGraph::Runner.new(graph: graph, context: context).call

    assert_same context, result
    assert_equal "completed", context.status
    assert_nil context.current_node
    assert_equal "original", context.state.dig("nested", "input")
    assert_equal true, context.state["prepared"]
    assert_equal "done", context.state["answer"]
    assert_equal [ "prepare", "finish" ], context.completed_nodes
  end

  def test_rejects_an_incomplete_context_before_execution
    error = assert_raises(ArgumentError) do
      AgentGraph::Core::Runner.new(graph: Object.new, context: Object.new)
    end

    assert_includes error.message, "invalid AgentGraph context"
    assert_includes error.message, "validate_graph!"
    assert_includes error.message, "invoke_node"
    assert_includes error.message, "finish_cancelled!"
  end

  class PrepareNode
    def call(state:)
      state["nested"]["input"] = "mutated copy"
      AgentGraph::NodeResult.next(updates: { prepared: true })
    end
  end

  class FinishNode
    def call(state:)
      AgentGraph::NodeResult.end(updates: { answer: state["prepared"] ? "done" : "missing" })
    end
  end

  class InMemoryContext
    NodeRun = Struct.new(:node_name)

    attr_reader :completed_nodes, :current_node, :state, :status

    def initialize(current_node:, state:)
      @current_node = current_node
      @state = state
      @status = "pending"
      @completed_nodes = []
    end

    def validate_graph!; end

    def result
      self
    end

    def start_run!
      @status = "running"
    end

    def running?
      status == "running"
    end

    def update_current_node!(node_name)
      @current_node = node_name
    end

    def check_cancelled!; end

    def cancelled_exception?(error)
      error.is_a?(AgentGraph::Cancelled)
    end

    def node_started!(_node_name); end

    def create_node_run!(node_name:, input_state:)
      NodeRun.new(node_name)
    end

    def complete_node_run!(node_run, result:)
      @completed_nodes << node_run.node_name
    end

    def fail_node_run!(_node_run, message:); end

    def apply_result!(_node_name, result)
      @state = deep_merge(state, result.updates)
    end

    def invoke_node(node, state:)
      node.call(state: state)
    end

    def finish_completed!
      @status = "completed"
      @current_node = nil
    end

    def finish_failed!(_message)
      @status = "failed"
    end

    def finish_cancelled!
      @status = "cancelled"
    end

    def interrupt!(node_name)
      @status = "awaiting_approval"
      @current_node = node_name
    end

    private

    def deep_merge(left, right)
      left.merge(right) do |_key, old_value, new_value|
        old_value.is_a?(Hash) && new_value.is_a?(Hash) ? deep_merge(old_value, new_value) : new_value
      end
    end
  end
end
