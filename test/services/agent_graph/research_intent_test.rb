# frozen_string_literal: true

require "test_helper"

class AgentGraphResearchIntentTest < ActiveSupport::TestCase
  test "matches research keywords" do
    assert AgentGraph::ResearchIntent.match?("調査日の根拠はどこから？")
    assert AgentGraph::ResearchIntent.match?("出典を確認して")
    assert AgentGraph::ResearchIntent.match?("Please research the origin")
  end

  test "ignores ordinary chat" do
    refute AgentGraph::ResearchIntent.match?("こんにちは")
    refute AgentGraph::ResearchIntent.match?("この画像は何？")
  end
end
