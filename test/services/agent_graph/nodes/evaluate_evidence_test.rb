# frozen_string_literal: true

require "test_helper"

class AgentGraphNodesEvaluateEvidenceTest < ActiveSupport::TestCase
  test "requests web search when web evidence is needed but missing" do
    result = node.call(state: state(
      plan: { "need_web" => true },
      budget: { "searches_used" => 0, "max_searches" => 2, "fetches_used" => 0, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "needs_web", result.updates.dig("evidence_review", "status")
    assert_equal true, result.updates.dig("plan", "need_web")
    assert_equal 1, result.updates.dig("evidence_review", "attempts")
  end

  test "requests page fetch for unfetched search result urls" do
    result = node.call(state: state(
      search_results: [ { "results" => [ { "url" => "https://example.com/a" } ] } ],
      budget: { "searches_used" => 1, "max_searches" => 2, "fetches_used" => 0, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "needs_fetch", result.updates.dig("evidence_review", "status")
    assert_equal [ "https://example.com/a" ], result.updates.dig("plan", "fetch_urls")
  end

  test "marks evidence sufficient when fetched pages exist" do
    result = node.call(state: state(
      fetched_pages: [ { "url" => "https://example.com/a", "content_preview" => "本文" } ],
      budget: { "searches_used" => 1, "max_searches" => 2, "fetches_used" => 1, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "sufficient", result.updates.dig("evidence_review", "status")
    assert_includes result.updates.dig("evidence_review", "reason"), "fetched pages"
  end

  test "marks evidence limited when retrieval was attempted and no budget remains" do
    result = node.call(state: state(
      plan: { "need_web" => true },
      search_results: [],
      budget: { "searches_used" => 1, "max_searches" => 1, "fetches_used" => 0, "max_fetches" => 0 }
    ), run: nil, chat: nil)

    assert_equal "limited", result.updates.dig("evidence_review", "status")
  end

  test "marks evidence limited after retry limit" do
    result = node.call(state: state(
      plan: { "need_web" => true },
      evidence_review: { "attempts" => AgentGraph::Nodes::EvaluateEvidence::MAX_ATTEMPTS },
      budget: { "searches_used" => 0, "max_searches" => 2, "fetches_used" => 0, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "limited", result.updates.dig("evidence_review", "status")
    assert_includes result.updates.dig("evidence_review", "reason"), "retry limit"
  end

  private

  def node
    AgentGraph::Nodes::EvaluateEvidence.new
  end

  def state(plan: {}, memo_context: nil, search_results: [], fetched_pages: [], evidence_review: {}, budget: {})
    {
      "plan" => plan,
      "memo_context" => memo_context,
      "search_results" => search_results,
      "fetched_pages" => fetched_pages,
      "evidence_review" => evidence_review,
      "budget" => budget,
      "errors" => []
    }
  end
end
