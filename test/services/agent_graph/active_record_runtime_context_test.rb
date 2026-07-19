# frozen_string_literal: true

require "test_helper"

class AgentGraphActiveRecordRuntimeContextTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: "test_graph",
      status: "pending",
      current_node: "start",
      state: {}
    )
    @graph = AgentGraph::GraphDefinition.new(
      name: "test_graph",
      start_node: "start",
      nodes: {},
      edges: {}
    )
  end

  test "builds runtime context from active record adapters" do
    context = AgentGraph::ActiveRecordRuntimeContext.build(run: @run, graph: @graph)

    assert_instance_of AgentGraph::RuntimeContext, context
    assert_instance_of AgentGraph::ActiveRecordRunStore, context.store
    assert_instance_of AgentGraph::RailsRuntimeSignals, context.signals
    assert_equal @run, context.result
  end
end
