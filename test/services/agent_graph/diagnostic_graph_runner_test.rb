# frozen_string_literal: true

require "test_helper"

class AgentGraphDiagnosticGraphRunnerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "runs diagnostic graph through registry registration" do
    run = AgentGraph::DiagnosticGraphRunner.call(@chat, note: "registry smoke")

    assert run.completed?, -> { run.error_message }
    assert_equal AgentGraph::DiagnosticGraph::NAME, run.graph_name
    assert_equal [ "record_diagnostic" ], run.agent_node_runs.order(:id).pluck(:node_name)
    assert_equal "Diagnostic Graph completed: registry smoke", run.state["final_answer"]
  end

  test "diagnostic summary is available through registry" do
    run = AgentGraph::DiagnosticGraphRunner.call(@chat, note: "summary smoke")

    summary = AgentGraph::Registry.summary_for(AgentGraph::DiagnosticGraph::NAME).build(run)

    assert_equal run.id, summary[:agent_run_id]
    assert_equal "summary smoke", summary[:note]
    assert_equal "Diagnostic Graph completed: summary smoke", summary[:final_answer]
    assert summary[:completed]
    assert_not summary[:failed]
    assert summary[:auto_approve]
  end
end
