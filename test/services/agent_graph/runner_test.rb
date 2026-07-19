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

    actual_graph = graph(name: "actual_graph")
    error = assert_raises(ArgumentError) do
      AgentGraph::Runner.new(
        graph: actual_graph,
        context: AgentGraph::ActiveRecordRuntimeContext.build(run: run, graph: actual_graph)
      ).call
    end

    assert_equal "agent run graph mismatch: expected_graph != actual_graph", error.message
    assert_equal "failed", run.reload.status
    assert_equal "agent run graph mismatch: expected_graph != actual_graph", run.error_message
    assert_empty run.agent_node_runs
  end

  test "uses injected runtime context for node execution hooks" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: "test_graph",
      status: "pending",
      current_node: "start",
      state: { "input" => "ok" }
    )
    context = RecordingContext.new(run: run)

    AgentGraph::Runner.new(graph: graph(name: "test_graph"), context: context).call

    assert_equal "completed", run.reload.status
    assert_equal [
      :validate_graph,
      :start_run,
      :check_cancelled,
      [ :node_started, "start" ],
      [ :create_node_run, "start" ],
      [ :complete_node_run, "start" ],
      [ :apply_result, "start" ],
      :finish_completed
    ], context.events
  end

  test "requires runtime context" do
    error = assert_raises(ArgumentError) do
      AgentGraph::Runner.new(graph: graph(name: "test_graph"))
    end

    assert_match(/missing keyword: :context/, error.message)
  end

  test "finishes run as cancelled when runtime context raises graph cancellation" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: "test_graph",
      status: "pending",
      current_node: "start",
      state: {}
    )
    context = RecordingContext.new(run: run, cancel_on_check: true)

    assert_raises(AgentGraph::Cancelled) do
      AgentGraph::Runner.new(graph: graph(name: "test_graph"), context: context).call
    end

    assert_equal "cancelled", run.reload.status
    assert_equal [ :validate_graph, :start_run, :check_cancelled, :finish_cancelled ], context.events
    assert_empty run.agent_node_runs
  end

  test "converts legacy chat cancellation raised by node into graph cancellation" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: "test_graph",
      status: "pending",
      current_node: "start",
      state: {}
    )

    assert_raises(AgentGraph::Cancelled) do
      legacy_graph = graph(name: "test_graph", node: LegacyCancellingNode.new)
      AgentGraph::Runner.new(
        graph: legacy_graph,
        context: AgentGraph::ActiveRecordRuntimeContext.build(run: run, graph: legacy_graph)
      ).call
    end

    assert_equal "cancelled", run.reload.status
    assert_equal "cancelled", run.error_message
    assert_equal "failed", run.agent_node_runs.last.status
  end

  private

  def graph(name:, node: Node.new)
    AgentGraph::GraphDefinition.new(
      name: name,
      start_node: "start",
      nodes: { "start" => node },
      edges: { "start" => AgentGraph::Edge.end }
    )
  end

  class Node
    def call(state:, run:, chat:)
      AgentGraph::NodeResult.end
    end
  end

  class LegacyCancellingNode
    def call(state:, run:, chat:)
      raise ChatResponseControl::Cancelled
    end
  end

  class RecordingContext
    attr_reader :events

    def initialize(run:, cancel_on_check: false)
      @run = run
      @cancel_on_check = cancel_on_check
      @events = []
    end

    def validate_graph!
      @events << :validate_graph
    end

    def result
      @run
    end

    def start_run!
      @events << :start_run
      @run.update!(status: "running", current_node: "start")
    end

    def current_node
      @run.current_node
    end

    def running?
      @run.running?
    end

    def update_current_node!(node_name)
      @events << [ :update_current_node, node_name ]
      @run.update!(current_node: node_name)
    end

    def check_cancelled!
      @events << :check_cancelled
      raise AgentGraph::Cancelled if @cancel_on_check
    end

    def cancelled_exception?(error)
      error.is_a?(AgentGraph::Cancelled)
    end

    def node_started!(node_name)
      @events << [ :node_started, node_name ]
    end

    def create_node_run!(node_name:, input_state:)
      @events << [ :create_node_run, node_name ]
      @run.agent_node_runs.create!(
        node_name: node_name,
        status: "running",
        input_snapshot: input_state,
        started_at: Time.current
      )
    end

    def complete_node_run!(node_run, result:)
      @events << [ :complete_node_run, node_run.node_name ]
      node_run.update!(
        status: result.failed? ? "failed" : "completed",
        output_snapshot: result.updates,
        error_message: result.error,
        finished_at: Time.current
      )
    end

    def fail_node_run!(node_run, message:)
      @events << [ :fail_node_run, node_run&.node_name, message ]
      node_run&.update!(status: "failed", error_message: message, finished_at: Time.current)
    end

    def state
      @run.state || {}
    end

    def apply_result!(node_name, result)
      @events << [ :apply_result, node_name ]
      @run.update!(state: state.deep_merge(result.updates))
      @run.agent_checkpoints.create!(node_name: node_name, state: @run.state)
    end

    def request_approval!
      @events << :request_approval
    end

    def node_call_kwargs(state:)
      { state: state, run: @run, chat: @run.chat }
    end

    def finish_completed!
      @events << :finish_completed
      @run.update!(status: "completed", current_node: nil, finished_at: Time.current)
    end

    def interrupt!(node_name)
      @events << [ :interrupt, node_name ]
      @run.update!(status: "awaiting_approval", current_node: node_name, finished_at: nil)
      request_approval!
    end

    def finish_failed!(message)
      @events << [ :finish_failed, message ]
      @run.update!(status: "failed", error_message: message.to_s, finished_at: Time.current)
      @run
    end

    def finish_cancelled!
      @events << :finish_cancelled
      @run.update!(status: "cancelled", finished_at: Time.current, error_message: "cancelled")
    end
  end
end
