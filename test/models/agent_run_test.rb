# frozen_string_literal: true

require "test_helper"

class AgentRunTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "state_summary lists top-level state keys" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "finalize_answer",
      state: { "question" => "q", "draft" => "d" }
    )

    assert_equal "state: question, draft", run.state_summary
  end

  test "recovery_candidates summarize failed node and latest checkpoint" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      state: { "question" => "q" }
    )
    failed_node = run.agent_node_runs.create!(
      node_name: "finalize_answer",
      status: "failed",
      error_message: "connection failed"
    )
    checkpoint = run.agent_checkpoints.create!(
      node_name: "synthesize_draft",
      state: { "question" => "q", "draft" => "d" }
    )

    assert_equal failed_node, run.failed_node_run
    assert_equal checkpoint, run.latest_checkpoint
    assert_includes run.recovery_candidates, "失敗 node: finalize_answer"
    assert_includes run.recovery_candidates, "最後の checkpoint: synthesize_draft ##{checkpoint.id}"
    assert_equal(
      "失敗 node: finalize_answer / 最後の checkpoint: synthesize_draft ##{checkpoint.id}",
      run.recovery_summary
    )
    assert_equal "connection failed", run.recovery_error_summary
  end

  test "retry source helpers summarize duplicate retry metadata" do
    source = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      state: { "question" => "q" }
    )
    retry_run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "finalize_answer",
      state: {
        "retry_of_agent_run_id" => source.id,
        "retry_from_checkpoint_id" => 123,
        "retry_from_node" => "synthesize_draft"
      }
    )

    assert retry_run.retry_run?
    assert_equal source, retry_run.retry_source_run
    assert_equal "retry of ##{source.id} / checkpoint #123 / from synthesize_draft", retry_run.retry_source_summary
  end
end
