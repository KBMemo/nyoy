# frozen_string_literal: true

require "test_helper"

class AgentGraphRunSummaryTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "research summary presents run state for MCP responses" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "completed",
      current_node: "finalize_answer",
      state: {
        "question" => "根拠を調べて",
        "draft" => "draft",
        "final_answer" => "answer",
        "approval" => nil,
        "assistant_message_id" => 123,
        "plan" => { "need_web" => true },
        "evidence_review" => { "status" => "limited", "reason" => "no more retrieval" },
        "budget" => { "searches_used" => 2, "max_searches" => 2 },
        "errors" => [],
        "auto_approve" => true
      }
    )
    run.agent_node_runs.create!(node_name: "plan_research", status: "completed")
    run.agent_node_runs.create!(node_name: "finalize_answer", status: "completed")

    summary = AgentGraph::ResearchRunSummary.build(run)

    assert_equal run.id, summary[:agent_run_id]
    assert_equal @chat.id, summary[:chat_id]
    assert_equal "根拠を調べて", summary[:question]
    assert_equal "answer", summary[:final_answer]
    assert_equal({ "need_web" => true }, summary[:plan])
    assert_equal({ "status" => "limited", "reason" => "no more retrieval" }, summary[:evidence_review])
    assert_equal({ "searches_used" => 2, "max_searches" => 2 }, summary[:budget])
    assert_equal %w[plan_research finalize_answer], summary[:nodes]
    assert_equal "/chats/#{@chat.id}", summary[:chat_path]
    assert_equal "/chats/#{@chat.id}/agent_runs/#{run.id}", summary[:agent_run_path]
    assert summary[:completed]
    assert_not summary[:failed]
    assert summary[:auto_approve]
  end

  test "memo write summary normalizes absent memo draft" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::MemoWriteGraph::NAME,
      status: "awaiting_approval",
      current_node: "await_approval",
      state: {
        "instruction" => "保存して",
        "draft" => "draft",
        "memo_draft" => nil,
        "approval" => "pending",
        "errors" => [],
        "auto_approve" => false
      }
    )
    run.agent_node_runs.create!(node_name: "plan_memo_write", status: "completed")
    run.agent_node_runs.create!(node_name: "await_approval", status: "completed")

    summary = AgentGraph::MemoWriteRunSummary.build(run)

    assert_equal run.id, summary[:agent_run_id]
    assert_equal "保存して", summary[:instruction]
    assert_equal({}, summary[:memo_draft])
    assert_nil summary[:memo_uid]
    assert_equal "pending", summary[:approval]
    assert_equal %w[plan_memo_write await_approval], summary[:nodes]
    assert summary[:awaiting_approval]
    assert_not summary[:completed]
    assert_not summary[:auto_approve]
  end

  test "memo update summary presents memo ref" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::MemoUpdateGraph::NAME,
      status: "completed",
      current_node: nil,
      state: {
        "instruction" => "更新して",
        "memo_ref" => "42",
        "draft" => "draft",
        "memo_draft" => { "memo_ref" => "42", "mode" => "append" },
        "memo_uid" => "42",
        "final_answer" => "updated",
        "approval" => "approved",
        "errors" => [],
        "auto_approve" => true
      }
    )
    run.agent_node_runs.create!(node_name: "plan_memo_update", status: "completed")

    summary = AgentGraph::MemoUpdateRunSummary.build(run)

    assert_equal run.id, summary[:agent_run_id]
    assert_equal "42", summary[:memo_ref]
    assert_equal({ "memo_ref" => "42", "mode" => "append" }, summary[:memo_draft])
    assert_equal "42", summary[:memo_uid]
    assert_equal [ "plan_memo_update" ], summary[:nodes]
    assert summary[:completed]
    assert summary[:auto_approve]
  end
end
