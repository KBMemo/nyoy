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
      graph_name: "memo_write",
      status: "awaiting_approval",
      current_node: "await_approval",
      state: {
        "instruction" => "これを徒然に保存して",
        "draft" => "### メモ\n本文",
        "memo_draft" => { "title" => "メモ", "body" => "本文" },
        "approval" => "pending"
      }
    )
  end

  test "approve via turbo_stream does not redirect" do
    assert_enqueued_with(job: AgentGraphResumeJob, args: [ @run.id, "approved" ]) do
      post approve_chat_agent_run_path(@chat, @run), as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, "agent_run_approval"
    assert_includes response.body, "徒然へ保存"
    assert_includes response.body, "new_message"
    assert @chat.reload.responding?
    assert_equal "approved", @run.reload.state["approval"]
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

  test "approve rejects unsupported research run" do
    @run.update!(
      graph_name: "research",
      state: {
        "question" => "調査の根拠を教えて",
        "draft" => "### 調査結果\n根拠メモ",
        "approval" => "pending"
      }
    )

    assert_no_enqueued_jobs only: AgentGraphResumeJob do
      post approve_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to @chat
    assert_match(/対応していません/, flash[:alert])
  end

  test "approve accepts memo update run" do
    @run.update!(
      graph_name: AgentGraph::MemoUpdateGraph::NAME,
      state: @run.state.merge(
        "memo_ref" => "42",
        "memo_draft" => {
          "memo_ref" => "42",
          "updated_at" => "2026-07-16T00:00:00Z",
          "mode" => "append",
          "append_body" => "追記"
        }
      )
    )

    assert_enqueued_with(job: AgentGraphResumeJob, args: [ @run.id, "approved" ]) do
      post approve_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to @chat
    assert_match(/更新を承認/, flash[:notice])
    assert_equal "approved", @run.reload.state["approval"]
  end

  test "approve rejects when not awaiting approval" do
    @run.update!(status: "completed")

    assert_no_enqueued_jobs only: AgentGraphResumeJob do
      post approve_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to @chat
    assert_match(/承認待ち/, flash[:alert])
  end

  test "approve uses memo notice" do
    post approve_chat_agent_run_path(@chat, @run)

    assert_redirected_to @chat
    assert_match(/徒然へ保存/, flash[:notice])
  end

  test "show omits approval panel after decision is submitted" do
    post approve_chat_agent_run_path(@chat, @run)
    get chat_path(@chat)

    assert_response :success
    assert_select "#agent_run_approval_panel", count: 0
  end

  test "show renders memo write approval panel for pending memo write run" do
    get chat_path(@chat)

    assert_response :success
    assert_select "#agent_run_approval_panel"
    assert_select "h2", text: "徒然メモの確認"
    assert_select "button, input[type=submit]", text: /この内容で徒然に保存する/
    assert_no_match(/却下してやり直す/, response.body)
  end

  test "show renders memo update approval panel" do
    @run.update!(
      graph_name: AgentGraph::MemoUpdateGraph::NAME,
      state: @run.state.merge(
        "memo_ref" => "42",
        "memo_draft" => {
          "memo_ref" => "42",
          "updated_at" => "2026-07-16T00:00:00Z",
          "mode" => "append",
          "append_body" => "追記"
        }
      )
    )

    get chat_path(@chat)

    assert_response :success
    assert_select "#agent_run_approval_panel"
    assert_select "button, input[type=submit]", text: /この内容で徒然メモを更新する/
  end

  test "show omits pending research approval panel" do
    @run.update!(
      graph_name: "research",
      state: {
        "question" => "調査の根拠を教えて",
        "draft" => "### 調査結果\n根拠メモ",
        "approval" => "pending"
      }
    )

    get chat_path(@chat)

    assert_response :success
    assert_select "#agent_run_approval_panel", count: 0
  end
end
