# frozen_string_literal: true

require "test_helper"

class AgentGraphActiveRecordRunStoreTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: "test_graph",
      status: "pending",
      current_node: nil,
      state: {}
    )
    @graph = AgentGraph::GraphDefinition.new(
      name: "test_graph",
      start_node: "start",
      nodes: {},
      edges: {}
    )
    @store = AgentGraph::ActiveRecordRunStore.new(run: @run, graph: @graph)
  end

  test "starts run at graph start node when current node is blank" do
    @store.start_run!

    assert_equal "running", @run.reload.status
    assert_equal "start", @run.current_node
    assert_not_nil @run.started_at
  end

  test "validates graph name against persisted run" do
    assert_nothing_raised { @store.validate_graph! }

    other_graph = AgentGraph::GraphDefinition.new(
      name: "other_graph",
      start_node: "start",
      nodes: {},
      edges: {}
    )
    store = AgentGraph::ActiveRecordRunStore.new(run: @run, graph: other_graph)

    error = assert_raises(ArgumentError) { store.validate_graph! }
    assert_equal "agent run graph mismatch: test_graph != other_graph", error.message
  end

  test "returns persisted run as execution result" do
    assert_equal @run, @store.result
  end

  test "creates node runs with scrubbed input snapshots" do
    node_run = @store.create_node_run!(
      node_name: "start",
      input_state: { "text" => "a\u0000b", "nested" => [ "c\u0000d" ] }
    )

    assert_equal "running", node_run.status
    assert_equal({ "text" => "ab", "nested" => [ "cd" ] }, node_run.input_snapshot)
  end

  test "builds legacy node call kwargs from rails run context" do
    state = { "foo" => "bar" }

    assert_equal({
      state: state,
      run: @run,
      chat: @chat
    }, @store.node_call_kwargs(state: state))
  end

  test "applies node results and checkpoints scrubbed state" do
    result = AgentGraph::NodeResult.new(updates: { "answer" => "ok\u0000" })

    @store.apply_result!("start", result)

    assert_equal({ "answer" => "ok" }, @run.reload.state)
    checkpoint = @run.agent_checkpoints.last
    assert_equal "start", checkpoint.node_name
    assert_equal({ "answer" => "ok" }, checkpoint.state)
  end
end
