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

  test "creates node runs with scrubbed input snapshots" do
    context = AgentGraph::RuntimeContext.new(run: @run, graph: @graph)

    node_run = context.create_node_run!(
      node_name: "start",
      input_state: { "text" => "a\u0000b", "nested" => [ "c\u0000d" ] }
    )

    assert_equal "running", node_run.status
    assert_equal({ "text" => "ab", "nested" => [ "cd" ] }, node_run.input_snapshot)
  end

  test "applies node results and checkpoints scrubbed state" do
    context = AgentGraph::RuntimeContext.new(run: @run, graph: @graph)
    result = AgentGraph::NodeResult.new(updates: { "answer" => "ok\u0000" })

    context.apply_result!("start", result)

    assert_equal({ "answer" => "ok" }, @run.reload.state)
    checkpoint = @run.agent_checkpoints.last
    assert_equal "start", checkpoint.node_name
    assert_equal({ "answer" => "ok" }, checkpoint.state)
  end
end
