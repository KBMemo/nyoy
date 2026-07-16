# frozen_string_literal: true

require "test_helper"

class AgentNodeRunTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "finalize_answer",
      state: {}
    )
  end

  test "output_summary reports common node result fields" do
    node_run = @run.agent_node_runs.create!(
      node_name: "finalize_answer",
      status: "failed",
      output_snapshot: {
        "updates" => { "final_answer" => "answer", "truncated" => false },
        "goto" => "done",
        "interrupt" => true,
        "error" => "boom"
      }
    )

    assert_equal [
      "updates: final_answer, truncated",
      "goto: done",
      "interrupt",
      "error: boom"
    ], node_run.output_summary
  end

  test "output_summary reports empty output" do
    node_run = @run.agent_node_runs.create!(
      node_name: "plan_research",
      status: "completed",
      output_snapshot: {}
    )

    assert_equal [ "no output" ], node_run.output_summary
  end
end
