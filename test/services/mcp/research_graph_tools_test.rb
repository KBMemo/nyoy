# frozen_string_literal: true

require "test_helper"

class McpResearchGraphToolsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
  end

  test "catalog includes research graph tools" do
    tools = Mcp::ToolCatalog.tools(server_context: {
      web_budget: ChatTools::WebToolBudget.from_settings,
      tool_instances: {}
    })
    names = tools.map(&:name_value)

    assert_includes names, "run_research_graph"
    assert_includes names, "get_research_graph"
    assert_includes names, "retry_research_graph"
    refute_includes names, "resume_research_graph"
  end

  test "run_research_graph auto_approve completes with final answer" do
    stub_research_nodes do
      response = Mcp::ResearchGraphTools.run_research_graph_tool.call(
        question: "調査日の根拠はどこ？"
      )
      payload = JSON.parse(response.content.first[:text])

      assert payload["agent_run_id"].present?
      assert_equal "completed", payload["status"]
      assert payload["final_answer"].present?
      assert_equal true, payload["completed"]
      refute payload["awaiting_approval"]
      assert_includes payload["nodes"], "finalize_answer"
    end
  end

  test "run_research_graph without auto_approve still completes immediately" do
    stub_research_nodes do
      response = Mcp::ResearchGraphTools.run_research_graph_tool.call(
        question: "出典を調べて",
        auto_approve: false
      )
      payload = JSON.parse(response.content.first[:text])

      assert_equal "completed", payload["status"]
      assert payload["final_answer"].present?
      assert_equal true, payload["completed"]
      refute payload["awaiting_approval"]
      assert_includes payload["nodes"], "finalize_answer"
    end
  end

  test "get_research_graph returns summary" do
    stub_research_nodes do
      run = AgentGraph::ResearchGraphRunner.call_for_mcp(
        question: "根拠は？",
        auto_approve: true
      )

      response = Mcp::ResearchGraphTools.get_research_graph_tool.call(agent_run_id: run.id)
      payload = JSON.parse(response.content.first[:text])

      assert_equal run.id, payload["agent_run_id"]
      assert_equal "completed", payload["status"]
    end
  end

  test "get_research_graph errors for missing id" do
    response = Mcp::ResearchGraphTools.get_research_graph_tool.call(agent_run_id: 0)

    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert payload["error"].present?
  end

  test "retry_research_graph launches duplicate run" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    run = AgentRun.create!(
      chat: chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      state: { "question" => "根拠は？", "draft" => "回答草案" },
      error_message: "failed"
    )
    completed = run.agent_node_runs.create!(
      node_name: "synthesize_draft",
      status: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    checkpoint = run.agent_checkpoints.create!(
      node_name: completed.node_name,
      state: run.state.merge("next_node" => "finalize_answer"),
      created_at: completed.finished_at + 1.second
    )
    run.agent_node_runs.create!(node_name: "finalize_answer", status: "failed")

    stub_synthesize_without_llm do
      response = Mcp::ResearchGraphTools.retry_research_graph_tool.call(agent_run_id: run.id)
      payload = JSON.parse(response.content.first[:text])

      assert_not response.error?
      assert_equal "completed", payload["status"]
      assert_not_equal run.id, payload["agent_run_id"]
      retry_run = AgentRun.find(payload["agent_run_id"])
      assert_equal run.id, retry_run.state["retry_of_agent_run_id"]
      assert_equal checkpoint.id, retry_run.state["retry_from_checkpoint_id"]
      assert_equal "synthesize_draft", retry_run.state["retry_from_node"]
    end
  end

  test "retry_research_graph returns planner errors" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    run = AgentRun.create!(
      chat: chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "plan_research",
      state: { "question" => "根拠は？" },
      error_message: "failed"
    )
    run.agent_node_runs.create!(node_name: "plan_research", status: "failed")

    response = Mcp::ResearchGraphTools.retry_research_graph_tool.call(agent_run_id: run.id)
    payload = JSON.parse(response.content.first[:text])

    assert response.error?
    assert_match "成功済み checkpoint", payload["error"]
  end

  private

  def stub_research_nodes
    stub_recall(context: "メモ抜粋") do
      stub_synthesize_without_llm do
        yield
      end
    end
  end

  def stub_recall(context: nil, error: nil)
    original = ChatTools::RecallMemos.instance_method(:execute)
    ChatTools::RecallMemos.define_method(:execute) do |query:|
      error ? { error: error } : { context: context }
    end
    yield
  ensure
    ChatTools::RecallMemos.define_method(:execute, original)
  end

  def stub_synthesize_without_llm
    previous_draft = AgentGraph::EvidenceSynthesizer.force_template
    previous_final = AgentGraph::FinalAnswerSynthesizer.force_passthrough
    AgentGraph::EvidenceSynthesizer.force_template = true
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = true
    yield
  ensure
    AgentGraph::EvidenceSynthesizer.force_template = previous_draft
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = previous_final
  end
end
