# frozen_string_literal: true

require "test_helper"

class AgentGraphRetryJobTest < ActiveJob::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"), response_state: "running")
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      state: { "question" => "q" },
      error_message: "failed"
    )
  end

  test "calls retry launcher and resets chat response state" do
    retry_run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "completed",
      current_node: nil,
      state: { "retry_of_agent_run_id" => @run.id }
    )
    calls = []
    original = AgentGraph::RunRetryLauncher.method(:call)
    AgentGraph::RunRetryLauncher.define_singleton_method(:call) do |run|
      calls << run.id
      retry_run
    end

    AgentGraphRetryJob.perform_now(@run.id)

    assert_equal [ @run.id ], calls
    assert_equal "idle", @chat.reload.response_state
  ensure
    AgentGraph::RunRetryLauncher.define_singleton_method(:call, original) if defined?(original) && original
  end
end
