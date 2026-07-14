# frozen_string_literal: true

require "test_helper"

class AgentRunsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @chat.messages.create!(role: :user, content: "調査の根拠を教えて")
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: "research",
      status: "awaiting_approval",
      current_node: "await_approval",
      state: {
        "question" => "調査の根拠を教えて",
        "draft" => "### 調査結果\n根拠メモ",
        "approval" => "pending"
      }
    )
  end

  test "approve enqueues resume job and clears pending decision" do
    assert_enqueued_with(job: AgentGraphResumeJob, args: [ @run.id, "approved" ]) do
      post approve_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to @chat
    assert @chat.reload.responding?
    assert_equal "approved", @run.reload.state["approval"]
    assert_equal 0, @chat.agent_runs.pending_decision.count
  end

  test "reject enqueues resume job" do
    assert_enqueued_with(job: AgentGraphResumeJob, args: [ @run.id, "rejected" ]) do
      post reject_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to @chat
    assert_equal "rejected", @run.reload.state["approval"]
  end

  test "approve rejects when not awaiting approval" do
    @run.update!(status: "completed")

    assert_no_enqueued_jobs only: AgentGraphResumeJob do
      post approve_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to @chat
    assert_match(/承認待ち/, flash[:alert])
  end

  test "show omits approval panel after decision is submitted" do
    post approve_chat_agent_run_path(@chat, @run)
    get chat_path(@chat)

    assert_response :success
    assert_select "#research_approval_panel", count: 0
  end
end
