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
    assert_includes names, "resume_research_graph"
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

  test "run_research_graph without auto_approve awaits then resumes" do
    stub_research_nodes do
      response = Mcp::ResearchGraphTools.run_research_graph_tool.call(
        question: "出典を調べて",
        auto_approve: false
      )
      payload = JSON.parse(response.content.first[:text])

      assert_equal "awaiting_approval", payload["status"]
      assert payload["draft"].present?
      assert payload["note"].present?

      resume = Mcp::ResearchGraphTools.resume_research_graph_tool.call(
        agent_run_id: payload["agent_run_id"],
        decision: "approved"
      )
      done = JSON.parse(resume.content.first[:text])

      assert_equal "completed", done["status"]
      assert_equal payload["draft"], done["final_answer"]
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
    original = AgentGraph::EvidenceSynthesizer.instance_method(:llm_synthesize)
    AgentGraph::EvidenceSynthesizer.define_method(:llm_synthesize) { |*| [ nil, false ] }
    yield
  ensure
    AgentGraph::EvidenceSynthesizer.define_method(:llm_synthesize, original)
  end
end
