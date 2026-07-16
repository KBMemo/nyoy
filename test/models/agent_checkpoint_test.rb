# frozen_string_literal: true

require "test_helper"

class AgentCheckpointTest < ActiveSupport::TestCase
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

  test "state_summary lists top-level state keys" do
    checkpoint = @run.agent_checkpoints.create!(
      node_name: "finalize_answer",
      state: { "question" => "q", "final_answer" => "a" }
    )

    assert_equal "state: question, final_answer", checkpoint.state_summary
  end

  test "state_summary reports empty state" do
    checkpoint = @run.agent_checkpoints.create!(node_name: "plan_research", state: {})

    assert_equal "empty state", checkpoint.state_summary
  end
end
