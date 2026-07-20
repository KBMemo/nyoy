# frozen_string_literal: true

require "test_helper"

class AgentGraphNodesEvaluateEvidenceTest < ActiveSupport::TestCase
  teardown do
    AgentGraph::RoleServices.reset!
  end

  test "requests web search when web evidence is needed but missing" do
    result = node.call(state: state(
      plan: { "need_web" => true },
      budget: { "searches_used" => 0, "max_searches" => 2, "fetches_used" => 0, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "needs_web", result.updates.dig("evidence_review", "status")
    assert_equal true, result.updates.dig("plan", "need_web")
    assert_equal 1, result.updates.dig("evidence_review", "attempts")
    assert_equal "search_web", result.updates.dig("evidence_review", "next_node")
    assert_equal "evidence_evaluator", result.updates.dig("evidence_review", "role")
    assert_equal "heuristic", result.updates.dig("evidence_review", "profile")
  end

  test "requests page fetch for unfetched search result urls" do
    result = node.call(state: state(
      search_results: [ { "results" => [ { "url" => "https://example.com/a" } ] } ],
      budget: { "searches_used" => 1, "max_searches" => 2, "fetches_used" => 0, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "needs_fetch", result.updates.dig("evidence_review", "status")
    assert_equal [ "https://example.com/a" ], result.updates.dig("plan", "fetch_urls")
    assert_equal "fetch_urls", result.updates.dig("evidence_review", "next_node")
    assert_equal [ "https://example.com/a" ], result.updates.dig("evidence_review", "target_urls")
  end

  test "requests followup search when previous search has no fetchable urls" do
    result = node.call(state: state(
      plan: {
        "need_web" => true,
        "queries" => [ "first query", "second query" ],
        "searched_queries" => [ "first query" ]
      },
      search_results: [ { "query" => "first query", "results" => [] } ],
      budget: { "searches_used" => 1, "max_searches" => 2, "fetches_used" => 0, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "needs_web", result.updates.dig("evidence_review", "status")
    assert_equal "search_web", result.updates.dig("evidence_review", "next_node")
    assert_includes result.updates.dig("evidence_review", "reason"), "previous web search"
  end

  test "requests only unfetched urls when plan still contains fetched urls" do
    result = node.call(state: state(
      plan: { "fetch_urls" => [ "https://example.com/a", "https://example.com/b" ] },
      budget: {
        "searches_used" => 1,
        "max_searches" => 2,
        "fetches_used" => 1,
        "max_fetches" => 3,
        "fetched_urls" => [ "https://example.com/a" ]
      }
    ), run: nil, chat: nil)

    assert_equal "needs_fetch", result.updates.dig("evidence_review", "status")
    assert_equal [ "https://example.com/b" ], result.updates.dig("plan", "fetch_urls")
    assert_equal [ "https://example.com/b" ], result.updates.dig("evidence_review", "target_urls")
  end

  test "marks evidence sufficient when fetched pages exist" do
    result = node.call(state: state(
      fetched_pages: [ { "url" => "https://example.com/a", "content_preview" => "本文" } ],
      budget: { "searches_used" => 1, "max_searches" => 2, "fetches_used" => 1, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "sufficient", result.updates.dig("evidence_review", "status")
    assert_includes result.updates.dig("evidence_review", "reason"), "fetched pages"
    assert_equal "synthesize_draft", result.updates.dig("evidence_review", "next_node")
  end

  test "does not search when an explicit URL page was already fetched" do
    result = node.call(state: state(
      plan: { "need_web" => true },
      fetched_pages: [ { "url" => "https://example.com/page", "content_preview" => "page body" } ],
      budget: { "searches_used" => 0, "max_searches" => 2, "fetches_used" => 1, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "sufficient", result.updates.dig("evidence_review", "status")
    assert_equal "synthesize_draft", result.updates.dig("evidence_review", "next_node")
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
      evidence_review: { "attempts" => AgentGraph::RoleServices::HeuristicEvidenceEvaluator::MAX_ATTEMPTS },
      budget: { "searches_used" => 0, "max_searches" => 2, "fetches_used" => 0, "max_fetches" => 2 }
    ), run: nil, chat: nil)

    assert_equal "limited", result.updates.dig("evidence_review", "status")
    assert_includes result.updates.dig("evidence_review", "reason"), "retry limit"
  end

  test "uses evidence evaluator role service" do
    calls = []
    service = Object.new
    service.define_singleton_method(:call) do |state:, run:, chat:|
      calls << { state: state, run: run, chat: chat }
      {
        status: "needs_fetch",
        reason: "custom evaluator",
        plan: { "fetch_urls" => [ "https://example.com/custom" ] },
        target_urls: [ "https://example.com/custom" ]
      }
    end

    AgentGraph::RoleServices.with(:evidence_evaluator, service) do
      result = node.call(state: state(plan: { "need_web" => true }), run: :run, chat: :chat)

      assert_equal "needs_fetch", result.updates.dig("evidence_review", "status")
      assert_equal "custom evaluator", result.updates.dig("evidence_review", "reason")
      assert_equal "fetch_urls", result.updates.dig("evidence_review", "next_node")
      assert_equal [ "https://example.com/custom" ], result.updates.dig("plan", "fetch_urls")
    end

    assert_equal 1, calls.size
    assert_equal true, calls.first.fetch(:state).dig("plan", "need_web")
    assert_equal :run, calls.first.fetch(:run)
    assert_equal :chat, calls.first.fetch(:chat)
  end

  test "records evaluator profile and optional runtime metadata" do
    service = Object.new
    service.define_singleton_method(:call) do |**|
      [
        {
          status: "sufficient",
          reason: "LLM review",
          plan: {},
          target_urls: []
        },
        {
          "source" => "light",
          "model_id" => "tiny",
          "fallback" => "heuristic",
          "usage" => { "input_tokens" => 40, "cached_tokens" => 25 }
        }
      ]
    end

    AgentGraph::RoleServices.with(:evidence_evaluator, service) do
      result = node.call(state: state, run: nil, chat: nil)
      review = result.updates.fetch("evidence_review")

      assert_equal "override", review.fetch("profile")
      assert_equal "light", review.fetch("source")
      assert_equal "tiny", review.fetch("model_id")
      assert_equal "heuristic", review.fetch("fallback")
      assert_equal 25, review.dig("usage", "cached_tokens")
    end
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
