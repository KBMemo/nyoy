# frozen_string_literal: true

require "test_helper"

class McpAgentGraphResponseTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "success serializes summary payload" do
    run = create_run(status: "completed")

    response = Mcp::AgentGraphResponse.success(run, summary: Summary)
    payload = JSON.parse(response.content.first[:text])

    assert_not response.error?
    assert_equal run.id, payload["agent_run_id"]
    assert_equal "completed", payload["status"]
  end

  test "success adds resume note for awaiting approval runs" do
    run = create_run(status: "awaiting_approval")

    response = Mcp::AgentGraphResponse.success(
      run,
      summary: Summary,
      resume_tool: "resume_test_graph"
    )
    payload = JSON.parse(response.content.first[:text])

    assert_includes payload["note"], "resume_test_graph(agent_run_id, decision)"
  end

  test "error serializes error payload" do
    response = Mcp::AgentGraphResponse.error("失敗しました")
    payload = JSON.parse(response.content.first[:text])

    assert response.error?
    assert_equal "失敗しました", payload["error"]
  end

  test "find_run scopes by graph name" do
    run = create_run(status: "completed", graph_name: "target_graph")
    create_run(status: "completed", graph_name: "other_graph")

    found = Mcp::AgentGraphResponse.find_run(run.id, graph_name: "target_graph")

    assert_equal run, found
    assert_nil Mcp::AgentGraphResponse.find_run(run.id, graph_name: "other_graph")
  end

  test "find_run_or_error returns run or mcp error response" do
    run = create_run(status: "completed", graph_name: "target_graph")

    found, found_error = Mcp::AgentGraphResponse.find_run_or_error(run.id, graph_name: "target_graph")
    missing, missing_error = Mcp::AgentGraphResponse.find_run_or_error(run.id, graph_name: "other_graph")

    assert_equal run, found
    assert_nil found_error
    assert_nil missing
    assert missing_error.error?
  end

  test "awaiting_run_or_error returns only awaiting approval runs" do
    waiting = create_run(status: "awaiting_approval", graph_name: "target_graph")
    completed = create_run(status: "completed", graph_name: "target_graph")

    found, found_error = Mcp::AgentGraphResponse.awaiting_run_or_error(waiting.id, graph_name: "target_graph")
    blocked, blocked_error = Mcp::AgentGraphResponse.awaiting_run_or_error(completed.id, graph_name: "target_graph")

    assert_equal waiting, found
    assert_nil found_error
    assert_nil blocked
    assert blocked_error.error?
  end

  test "common error helpers return mcp error responses" do
    missing = Mcp::AgentGraphResponse.missing_run(123)
    not_waiting = Mcp::AgentGraphResponse.not_awaiting_approval(create_run(status: "completed"))

    assert missing.error?
    assert not_waiting.error?
    assert_includes JSON.parse(missing.content.first[:text])["error"], "AgentRun 123"
    assert_includes JSON.parse(not_waiting.content.first[:text])["error"], "status=completed"
  end

  private

  def create_run(status:, graph_name: "test_graph")
    AgentRun.create!(
      chat: @chat,
      graph_name: graph_name,
      status: status,
      current_node: status == "awaiting_approval" ? "await_approval" : nil,
      state: {}
    )
  end

  class Summary
    def self.build(run)
      {
        agent_run_id: run.id,
        status: run.status
      }
    end
  end
end
