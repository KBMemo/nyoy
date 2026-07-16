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

  test "show renders agent run details" do
    node_run = @run.agent_node_runs.create!(
      node_name: "await_approval",
      status: "completed",
      started_at: 1.minute.ago,
      finished_at: Time.current,
      input_snapshot: { "input_marker" => "before" },
      output_snapshot: { "updates" => { "approval" => "pending" } }
    )
    @run.agent_checkpoints.create!(
      node_name: "await_approval",
      state: @run.state
    )

    get chat_agent_run_path(@chat, @run)

    assert_response :success
    assert_select "h1", text: "AgentRun ##{@run.id}"
    assert_select "dd", text: @run.graph_name
    assert_select "dd", text: @run.status
    assert_select "td", text: node_run.node_name
    assert_select "th", text: "Elapsed"
    assert_select "th", text: "Summary"
    assert_select "tr.nyoy-agent-node-row"
    assert_select "tr.nyoy-agent-node-detail-row"
    assert_select "td", text: /updates: approval/
    assert_select "td[colspan='7'] summary", text: /#{node_run.node_name} の snapshot/
    assert_select "summary", text: /JSON を表示/
    assert_includes response.body, "input_marker"
    assert_includes response.body, "updates"
    assert_includes response.body, "state:"
    assert_includes response.body, "instruction"
    assert_includes response.body, "memo_draft"
    assert_select "th", text: "Created"
    assert_select "td[colspan='4'] summary", text: /#{node_run.node_name} の state/
    assert_includes response.body, "memo_draft"
  end

  test "show renders retry source details" do
    source = @run
    retry_run = @chat.agent_runs.create!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "completed",
      current_node: nil,
      state: {
        "retry_of_agent_run_id" => source.id,
        "retry_from_checkpoint_id" => 456,
        "retry_from_node" => "synthesize_draft"
      }
    )

    get chat_agent_run_path(@chat, retry_run)

    assert_response :success
    assert_select "dt", text: "Retry Source"
    assert_select "a[href='#{chat_agent_run_path(@chat, source)}']", text: "AgentRun ##{source.id}"
    assert_select "dd", text: /checkpoint #456/
    assert_select "dd", text: /from synthesize_draft/
  end

  test "show renders failed run recovery hints" do
    @run.update!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      error_message: "モデルサーバーに接続できません"
    )
    completed_node = @run.agent_node_runs.create!(
      node_name: "synthesize_draft",
      status: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    checkpoint = @run.agent_checkpoints.create!(
      node_name: completed_node.node_name,
      state: @run.state.merge("draft" => "回答草案"),
      created_at: completed_node.finished_at + 1.second
    )
    failed_node = @run.agent_node_runs.create!(
      node_name: "finalize_answer",
      status: "failed",
      error_message: "connection failed"
    )

    get chat_agent_run_path(@chat, @run)

    assert_response :success
    assert_select "h2", text: "復旧確認"
    assert_select ".kb-alert-danger", text: /connection failed/
    assert_select "a[href='#agent_node_run_#{failed_node.id}']", text: "finalize_answer"
    assert_select "a[href='#agent_checkpoint_#{checkpoint.id}']", text: /##{checkpoint.id} synthesize_draft/
    assert_select "tr#agent_node_run_#{failed_node.id}"
    assert_select "tr#agent_checkpoint_#{checkpoint.id}"
    assert_select "td[colspan='7'] details[open] summary", text: /#{failed_node.node_name} の snapshot/
    assert_select "td[colspan='4'] details[open] summary", text: /#{checkpoint.node_name} の state/
    assert_select "h3", text: "Retry Dry-run"
    assert_select "p", text: /retry 候補/
    assert_select "a[href='#agent_checkpoint_#{checkpoint.id}']", text: /##{checkpoint.id} synthesize_draft/
    assert_select "p", text: /次 node: finalize_answer/
    assert_select "form[action='#{retry_chat_agent_run_path(@chat, @run)}']"
    assert_select "button, input[type=submit]", text: /複製 run で retry/
    assert_select "li", text: /最後の checkpoint: synthesize_draft/
    assert_select "li", text: /複製 run/
  end

  test "retry enqueues retry job for retryable failed run" do
    @run.update!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      error_message: "モデルサーバーに接続できません"
    )
    completed_node = @run.agent_node_runs.create!(
      node_name: "synthesize_draft",
      status: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    @run.agent_checkpoints.create!(
      node_name: completed_node.node_name,
      state: @run.state.merge("draft" => "回答草案"),
      created_at: completed_node.finished_at + 1.second
    )
    @run.agent_node_runs.create!(node_name: "finalize_answer", status: "failed")

    assert_enqueued_with(job: AgentGraphRetryJob, args: [ @run.id ]) do
      post retry_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to @chat
    assert_match(/retry を開始/, flash[:notice])
    assert @chat.reload.responding?
  end

  test "retry rejects blocked failed run" do
    @run.update!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "plan_research",
      error_message: "failed"
    )
    @run.agent_node_runs.create!(node_name: "plan_research", status: "failed")

    assert_no_enqueued_jobs only: AgentGraphRetryJob do
      post retry_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to chat_agent_run_path(@chat, @run)
    assert_match(/成功済み checkpoint/, flash[:alert])
    assert_not @chat.reload.responding?
  end

  test "retry rejects while another response is running" do
    @chat.update!(response_state: "running")
    @run.update!(
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "failed",
      current_node: "finalize_answer",
      error_message: "failed"
    )
    completed_node = @run.agent_node_runs.create!(
      node_name: "synthesize_draft",
      status: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    @run.agent_checkpoints.create!(
      node_name: completed_node.node_name,
      state: @run.state.merge("draft" => "回答草案"),
      created_at: completed_node.finished_at + 1.second
    )

    assert_no_enqueued_jobs only: AgentGraphRetryJob do
      post retry_chat_agent_run_path(@chat, @run)
    end

    assert_redirected_to chat_agent_run_path(@chat, @run)
    assert_match(/別の応答/, flash[:alert])
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
