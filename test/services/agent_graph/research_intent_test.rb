# frozen_string_literal: true

require "test_helper"

class AgentGraphResearchIntentTest < ActiveSupport::TestCase
  test "matches strong research framing" do
    assert_match_intent "調査日の根拠はどこから？"
    assert_match_intent "出典を確認して"
    assert_match_intent "最新情報を調べて"
    assert_match_intent "公式サイトを調べて Hydrangea Rin"
    assert_match_intent "Please research the origin"
    assert_match_intent "fact-check this claim"
    assert_match_intent "裏付けを取りたい"
  end

  test "matches URL with investigate framing" do
    assert_match_intent "このページを確認して https://docs.example.com/page"
    assert_match_intent "https://example.com/spec を要約して"
  end

  test "matches multiple weak cues" do
    assert_match_intent "公式ニュースを確認して"
  end

  test "ignores ordinary and non-research chat" do
    refute_match_intent "こんにちは"
    refute_match_intent "この画像は何？"
    refute_match_intent "猫のイラストを描いて"
    refute_match_intent "temperature を下げて"
    refute_match_intent "了解"
  end

  test "ignores bare URL without investigate framing" do
    refute_match_intent "https://example.com/"
  end

  test "ignores weak cue alone" do
    refute_match_intent "確認して"
    refute_match_intent "ニュースどう？"
  end

  test "decision exposes reason for debugging" do
    decision = AgentGraph::ResearchIntent.decision("出典を調べて")
    assert decision[:match]
    assert_equal "strong", decision[:reason]
    assert decision[:hits].any?
  end

  private

  def assert_match_intent(text)
    decision = AgentGraph::ResearchIntent.decision(text)
    assert decision[:match], -> { "expected match for #{text.inspect}, got #{decision.inspect}" }
  end

  def refute_match_intent(text)
    decision = AgentGraph::ResearchIntent.decision(text)
    refute decision[:match], -> { "expected no match for #{text.inspect}, got #{decision.inspect}" }
  end
end
