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
end
