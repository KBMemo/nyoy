# frozen_string_literal: true

require "test_helper"

class AgentGraphInitialStateTest < ActiveSupport::TestCase
  setup do
    model = Model.find_or_create_by!(provider: "test", model_id: "initial-state-test") do |record|
      record.name = "Initial State Test"
    end
    @chat = Chat.create!(model: model)
  end

  test "builds research initial state" do
    state = AgentGraph::ResearchInitialState.build(
      chat: @chat,
      question: "根拠を調べて",
      auto_approve: true
    )

    assert_equal "根拠を調べて", state["question"]
    assert_equal @chat.id, state["chat_id"]
    assert_equal "research", state["intent"]
    assert_equal AgentGraph::ResearchGraph::START, state["next_node"]
    assert_equal true, state["auto_approve"]
    assert_equal({}, state["plan"])
    assert_equal [], state["search_results"]
    assert_equal [], state["fetched_pages"]
    assert_equal({}, state["evidence_review"])
    assert_equal [], state["errors"]
  end

  test "builds memo write initial state" do
    state = AgentGraph::MemoWriteInitialState.build(
      chat: @chat,
      instruction: "これを保存して",
      auto_approve: true,
      mcp_body: "本文",
      mcp_title: "表題"
    )

    assert_equal "これを保存して", state["instruction"]
    assert_equal @chat.id, state["chat_id"]
    assert_equal "memo_write", state["intent"]
    assert_equal AgentGraph::MemoWriteGraph::START, state["next_node"]
    assert_equal true, state["auto_approve"]
    assert_equal "本文", state["mcp_body"]
    assert_equal "表題", state["mcp_title"]
    assert_equal({}, state["plan"])
    assert_nil state["memo_uid"]
    assert_equal [], state["errors"]
  end

  test "builds memo update initial state" do
    state = AgentGraph::MemoUpdateInitialState.build(
      chat: @chat,
      instruction: "メモ 42 に追記して",
      auto_approve: true,
      memo_ref: "42",
      body: "追記本文",
      title: "新タイトル",
      mode: "append"
    )

    assert_equal "メモ 42 に追記して", state["instruction"]
    assert_equal @chat.id, state["chat_id"]
    assert_equal "memo_update", state["intent"]
    assert_equal AgentGraph::MemoUpdateGraph::START, state["next_node"]
    assert_equal true, state["auto_approve"]
    assert_equal "42", state["mcp_memo_ref"]
    assert_equal "追記本文", state["mcp_body"]
    assert_equal "新タイトル", state["mcp_title"]
    assert_equal "append", state["mcp_mode"]
    assert_nil state["memo_uid"]
    assert_equal [], state["errors"]
  end

  test "research state schema rejects missing keys" do
    error = assert_raises(ArgumentError) do
      AgentGraph::ResearchStateSchema.validate!("question" => "根拠は？")
    end

    assert_includes error.message, "research state missing keys"
    assert_includes error.message, "chat_id"
  end

  test "memo write state schema rejects missing keys" do
    error = assert_raises(ArgumentError) do
      AgentGraph::MemoWriteStateSchema.validate!("instruction" => "保存して")
    end

    assert_includes error.message, "memo_write state missing keys"
    assert_includes error.message, "chat_id"
  end

  test "memo update state schema rejects missing keys" do
    error = assert_raises(ArgumentError) do
      AgentGraph::MemoUpdateStateSchema.validate!("instruction" => "更新して")
    end

    assert_includes error.message, "memo_update state missing keys"
    assert_includes error.message, "chat_id"
  end
end
