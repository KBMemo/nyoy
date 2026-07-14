# frozen_string_literal: true

require "test_helper"

class AgentGraphMemoWriteIntentTest < ActiveSupport::TestCase
  test "matches clear save-as-memo phrasing" do
    assert_match_intent "これを徒然に保存して"
    assert_match_intent "この回答をメモに保存して"
    assert_match_intent "メモにして"
    assert_match_intent "create_memo で保存"
    assert_match_intent "save this as a memo"
  end

  test "defers research-framed save to Research Graph" do
    refute_match_intent "出典を調べて徒然に保存する前提で確認してから答えて"
    refute_match_intent "根拠を調査してメモに保存して"
  end

  test "allows save of existing content even with mild research words" do
    assert_match_intent "この回答を徒然に保存して"
  end

  test "ignores ordinary chat" do
    refute_match_intent "こんにちは"
    refute_match_intent "猫のイラストを描いて"
    refute_match_intent "確認して"
  end

  test "decision exposes reason" do
    decision = AgentGraph::MemoWriteIntent.decision("メモに保存して")
    assert decision[:match]
    assert_equal "strong", decision[:reason]
  end

  private

  def assert_match_intent(text)
    decision = AgentGraph::MemoWriteIntent.decision(text)
    assert decision[:match], -> { "expected match for #{text.inspect}, got #{decision.inspect}" }
  end

  def refute_match_intent(text)
    decision = AgentGraph::MemoWriteIntent.decision(text)
    refute decision[:match], -> { "expected no match for #{text.inspect}, got #{decision.inspect}" }
  end
end
