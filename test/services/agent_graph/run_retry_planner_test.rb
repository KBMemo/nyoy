# frozen_string_literal: true

require "test_helper"

class AgentGraphRunRetryPlannerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "plans research retry from latest successful checkpoint" do
    run = create_run(graph_name: AgentGraph::ResearchGraph::NAME)
    completed = run.agent_node_runs.create!(
      node_name: "synthesize_draft",
      status: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    checkpoint = run.agent_checkpoints.create!(
      node_name: completed.node_name,
      state: {
        "question" => "q",
        "draft" => "d",
        "next_node" => "finalize_answer"
      },
      created_at: completed.finished_at + 1.second
    )
    run.agent_node_runs.create!(node_name: "finalize_answer", status: "failed")

    plan = AgentGraph::RunRetryPlanner.call(run)

    assert plan.retryable
    assert_equal "複製 run 候補", plan.reason
    assert_equal checkpoint, plan.checkpoint
    assert_equal "finalize_answer", plan.next_node
  end

  test "blocks write graph retry dry-run" do
    run = create_run(graph_name: AgentGraph::MemoWriteGraph::NAME)
    completed = run.agent_node_runs.create!(
      node_name: "draft_memo",
      status: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    checkpoint = run.agent_checkpoints.create!(
      node_name: completed.node_name,
      state: {
        "instruction" => "保存して",
        "memo_draft" => { "body" => "本文" }
      },
      created_at: completed.finished_at + 1.second
    )

    plan = AgentGraph::RunRetryPlanner.call(run)

    assert_not plan.retryable
    assert_match "write 系 Graph", plan.reason
    assert_equal checkpoint, plan.checkpoint
    assert_equal "await_approval", plan.next_node
  end

  test "blocks failed run without successful checkpoint" do
    run = create_run(graph_name: AgentGraph::ResearchGraph::NAME)
    run.agent_node_runs.create!(node_name: "plan_research", status: "failed")

    plan = AgentGraph::RunRetryPlanner.call(run)

    assert_not plan.retryable
    assert_equal "成功済み checkpoint がありません", plan.reason
    assert_nil plan.checkpoint
    assert_nil plan.next_node
  end

  private

  def create_run(graph_name:)
    AgentRun.create!(
      chat: @chat,
      graph_name: graph_name,
      status: "failed",
      current_node: "finalize_answer",
      state: { "question" => "q" },
      error_message: "failed"
    )
  end
end
