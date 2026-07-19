# frozen_string_literal: true

require "test_helper"

class AgentGraphCoreTest < ActiveSupport::TestCase
  test "core entrypoint exposes the public constants" do
    assert AgentGraph::Core.const_defined?(:Cancelled, false)
    assert AgentGraph::Core.const_defined?(:ContextProtocol, false)
    assert AgentGraph::Core.const_defined?(:Edge, false)
    assert AgentGraph::Core.const_defined?(:GraphDefinition, false)
    assert AgentGraph::Core.const_defined?(:NodeResult, false)
    assert AgentGraph::Core.const_defined?(:Runner, false)
    assert AgentGraph::Core.const_defined?(:StateSchema, false)
  end

  test "core graph definition uses string keys without ActiveSupport helpers" do
    graph = AgentGraph::Core::GraphDefinition.new(
      name: :sample,
      start_node: :start,
      nodes: { start: -> {} },
      edges: { start: AgentGraph::Core::Edge.new(to: ->(state) { state.fetch("next") }) }
    )

    assert_equal "sample", graph.name
    assert graph.node_for("start")
    assert_equal "done", graph.next_node_for(:start, { "next" => "done" })
  end

  test "core node result deep stringifies updates" do
    result = AgentGraph::Core::NodeResult.next(updates: {
      foo: { bar: [ { baz: "qux" } ] }
    })

    assert_equal({ "foo" => { "bar" => [ { "baz" => "qux" } ] } }, result.updates)
  end

  test "core context protocol exposes the runner contract" do
    assert_includes AgentGraph::Core::ContextProtocol::REQUIRED_METHODS, :invoke_node
    assert_includes AgentGraph::Core::ContextProtocol::REQUIRED_METHODS, :apply_result!
    assert_includes AgentGraph::Core::ContextProtocol::REQUIRED_METHODS, :finish_completed!
  end

  test "legacy constants point to core classes" do
    assert_same AgentGraph::Core::GraphDefinition, AgentGraph::GraphDefinition
    assert_same AgentGraph::Core::Edge, AgentGraph::Edge
    assert_same AgentGraph::Core::NodeResult, AgentGraph::NodeResult
    assert_same AgentGraph::Core::StateSchema, AgentGraph::StateSchema
    assert_same AgentGraph::Core::Cancelled, AgentGraph::Cancelled
    assert_same AgentGraph::Core::Runner, AgentGraph::Runner
  end
end
