# frozen_string_literal: true

require "test_helper"

class AgentGraphResearchRoutingTest < ActiveSupport::TestCase
  test "after_plan prefers recall then search then fetch" do
    assert_equal "recall_memos", AgentGraph::ResearchRouting.after_plan("need_memo" => true, "need_web" => true)
    assert_equal "search_web", AgentGraph::ResearchRouting.after_plan("need_memo" => false, "need_web" => true)
    assert_equal "fetch_urls", AgentGraph::ResearchRouting.after_plan(
      "need_memo" => false, "need_web" => false, "fetch_urls" => [ "https://example.com" ]
    )
    assert_equal "synthesize_draft", AgentGraph::ResearchRouting.after_plan("need_memo" => false, "need_web" => false)
  end

  test "fetch_targets prefers plan urls over search results" do
    state = {
      "plan" => { "fetch_urls" => [ "https://a.example" ] },
      "search_results" => [ { "results" => [ { "url" => "https://b.example" } ] } ]
    }

    assert_equal [ "https://a.example" ], AgentGraph::ResearchRouting.fetch_targets(state)
  end

  test "after_synthesize awaits approval unless auto_approve" do
    assert_equal "await_approval", AgentGraph::ResearchRouting.after_synthesize(
      "plan" => { "sensitive" => false }
    )
    assert_equal "await_approval", AgentGraph::ResearchRouting.after_synthesize(
      "plan" => { "sensitive" => true }
    )
    assert_equal "finalize_answer", AgentGraph::ResearchRouting.after_synthesize(
      "plan" => { "sensitive" => true },
      "auto_approve" => true
    )
    assert_equal "finalize_answer", AgentGraph::ResearchRouting.after_synthesize(
      "plan" => { "sensitive" => false },
      "auto_approve" => true
    )
  end
end
