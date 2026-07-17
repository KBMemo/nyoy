# frozen_string_literal: true

require "test_helper"

class AgentGraphRuntimeContextTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: "test_graph",
      status: "running",
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

  test "exposes legacy node call kwargs from the runtime boundary" do
    context = AgentGraph::RuntimeContext.new(run: @run, graph: @graph)
    state = { "foo" => "bar" }

    assert_equal({
      state: state,
      run: @run,
      chat: @chat
    }, context.node_call_kwargs(state: state))
  end

  test "chat is resolved through the run" do
    context = AgentGraph::RuntimeContext.new(run: @run, graph: @graph)

    assert_equal @chat, context.chat
  end
end
