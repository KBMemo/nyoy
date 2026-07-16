# frozen_string_literal: true

require "test_helper"

class AgentGraphMemoUpdateIntentTest < ActiveSupport::TestCase
  test "matches explicit memo update instructions" do
    assert_match_intent "メモ 42 に追記して\n新しい本文"
    assert_match_intent "徒然 01ABC を更新して"
    assert_match_intent "update_memo で修正"
  end

  test "does not match create memo instructions" do
    refute_match_intent "この回答を徒然に保存して"
  end

  test "defers research framed update requests" do
    decision = AgentGraph::MemoUpdateIntent.decision("根拠を調べてからメモ 42 を更新して")

    assert_not decision[:match]
    assert_equal "defer_research", decision[:reason]
  end

  private

  def assert_match_intent(text)
    assert AgentGraph::MemoUpdateIntent.match?(text), "Expected update intent for: #{text.inspect}"
  end

  def refute_match_intent(text)
    assert_not AgentGraph::MemoUpdateIntent.match?(text), "Expected no update intent for: #{text.inspect}"
  end
end
