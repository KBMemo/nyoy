# frozen_string_literal: true

require "test_helper"

class AgentGraphProgressBroadcasterTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    AppSetting.instance.update!(research_draft_model_id: "gpt-oss", research_draft_fallback: "main")
  end

  test "evidence pack progress omits model name" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "synthesize_draft",
      started_at: Time.current,
      state: { "question" => "調べて" }
    )

    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.started!(@chat, "synthesize_draft", agent_run: run)
    end.last

    assert_equal "agent_run_progress", payload["type"]
    assert_includes payload["label"], "根拠"
    assert_equal "synthesize_draft", payload["node_name"]
    assert_nil payload["model_name"]
    assert payload["node_started_at"].present?
    assert payload["run_started_at"].present?
    assert_includes payload["html"], "agent_run_progress_panel"
    assert_includes payload["html"], "根拠"
    refute_includes payload["html"], "gpt-oss"
    assert_includes payload["html"], "data-agent-run-progress-elapsed"
    assert_includes payload["html"], "data-agent-run-progress-run-elapsed"
  end

  test "finalize progress shows the chat main model" do
    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.started!(@chat, "finalize_answer")
    end.last

    assert_includes payload["label"], "最終回答"
    assert_equal "gpt-oss", payload["model_name"]
    assert_includes payload["html"], "gpt-oss"
  end

  test "search progress omits model name" do
    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.started!(@chat, "search_web")
    end.last

    assert_includes payload["label"], "Web"
    assert_nil payload["model_name"]
    refute_includes payload["html"], "gpt-oss"
  end

  test "clear broadcasts empty panel" do
    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.clear!(@chat)
    end.last

    assert_equal "agent_run_progress", payload["type"]
    assert_nil payload["label"]
    assert_equal "", payload["html"]
  end

  test "started panel includes hidden thinking mount" do
    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.started!(@chat, "finalize_answer")
    end.last

    assert_includes payload["html"], "agent_run_progress_thinking_section"
    assert_includes payload["html"], "agent_run_progress_thinking"
    assert_includes payload["html"], "hidden"
  end

  test "render_for_run restores running progress panel" do
    run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "finalize_answer",
      started_at: 2.minutes.ago,
      state: { "question" => "調べて" }
    )
    run.agent_node_runs.create!(
      node_name: "finalize_answer",
      status: "running",
      started_at: 30.seconds.ago
    )

    html = AgentGraph::ProgressBroadcaster.render_for_run(run)

    assert_includes html, "agent_run_progress_panel"
    assert_includes html, "最終回答"
    assert_includes html, "data-run-started-at"
    assert_includes html, "data-node-started-at"
  end

  test "thinking broadcasts text without replacing the panel" do
    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.thinking!(@chat, "まず調査ドラフトを読む…")
    end.last

    assert_equal "agent_run_progress_thinking", payload["type"]
    assert_equal "まず調査ドラフトを読む…", payload["text"]
    assert_nil payload["html"]
  end

  test "thinking ignores blank text" do
    assert_no_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.thinking!(@chat, "   ")
      AgentGraph::ProgressBroadcaster.thinking!(@chat, "")
    end
  end

  test "thinking bounds live payload while preserving the latest text" do
    limit = AgentGraph::ProgressBroadcaster::MAX_THINKING_BROADCAST_CHARS
    text = "old" + ("x" * limit) + "latest"

    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.thinking!(@chat, text)
    end.last

    assert payload["text"].start_with?(AgentGraph::ProgressBroadcaster::TRUNCATED_THINKING_PREFIX)
    assert payload["text"].end_with?("latest")
    assert_operator payload["text"].length, :<=, limit + 2
    assert_not_includes payload["text"], "old"
  end

  test "prompts broadcasts system and user text without replacing the panel" do
    payload = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      AgentGraph::ProgressBroadcaster.prompts!(
        @chat,
        system: "あなたは調査アシスタントです。",
        user: "質問:\n高尾山は？"
      )
    end.last

    assert_equal "agent_run_progress_prompts", payload["type"]
    assert_equal "あなたは調査アシスタントです。", payload["system"]
    assert_equal "質問:\n高尾山は？", payload["user"]
    assert_nil payload["html"]
  end
end
