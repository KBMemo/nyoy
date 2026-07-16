# frozen_string_literal: true

require "test_helper"

class AgentGraphResearchRoutingTest < ActiveSupport::TestCase
  test "after_plan prefers recall then search then fetch" do
    assert_equal "recall_memos", AgentGraph::ResearchRouting.after_plan("need_memo" => true, "need_web" => true)
    assert_equal "search_web", AgentGraph::ResearchRouting.after_plan("need_memo" => false, "need_web" => true)
    assert_equal "fetch_urls", AgentGraph::ResearchRouting.after_plan(
      "need_memo" => false, "need_web" => false, "fetch_urls" => [ "https://example.com" ]
    )
    assert_equal "evaluate_evidence", AgentGraph::ResearchRouting.after_plan("need_memo" => false, "need_web" => false)
  end

  test "after_recall falls through to evidence evaluation" do
    assert_equal "evaluate_evidence", AgentGraph::ResearchRouting.after_recall(
      "plan" => { "need_web" => false, "fetch_urls" => [] }
    )
  end

  test "after_search falls through to evidence evaluation when no fetch targets remain" do
    assert_equal "evaluate_evidence", AgentGraph::ResearchRouting.after_search(
      "plan" => { "fetch_urls" => [] },
      "search_results" => []
    )
  end

  test "after_evaluate routes to retrieval or synthesis by review status" do
    assert_equal "search_web", AgentGraph::ResearchRouting.after_evaluate(
      "evidence_review" => { "status" => "needs_web" }
    )
    assert_equal "fetch_urls", AgentGraph::ResearchRouting.after_evaluate(
      "evidence_review" => { "status" => "needs_fetch" }
    )
    assert_equal "synthesize_draft", AgentGraph::ResearchRouting.after_evaluate(
      "evidence_review" => { "status" => "sufficient" }
    )
    assert_equal "synthesize_draft", AgentGraph::ResearchRouting.after_evaluate(
      "evidence_review" => { "status" => "limited" }
    )
  end

  test "fetch_targets prefers plan urls over search results" do
    state = {
      "plan" => { "fetch_urls" => [ "https://a.example" ] },
      "search_results" => [ { "results" => [ { "url" => "https://b.example" } ] } ]
    }

    assert_equal [ "https://a.example" ], AgentGraph::ResearchRouting.fetch_targets(state)
  end

  test "after_synthesize always finalizes without approval" do
    assert_equal "finalize_answer", AgentGraph::ResearchRouting.after_synthesize(
      "plan" => { "sensitive" => false }
    )
    assert_equal "finalize_answer", AgentGraph::ResearchRouting.after_synthesize(
      "plan" => { "sensitive" => true }
    )
    assert_equal "finalize_answer", AgentGraph::ResearchRouting.after_synthesize(
      "plan" => { "sensitive" => true },
      "auto_approve" => false
    )
  end
end
