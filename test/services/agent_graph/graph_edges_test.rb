# frozen_string_literal: true

require "test_helper"

class AgentGraphGraphEdgesTest < ActiveSupport::TestCase
  test "graphs expose common definition contract" do
    graphs = [
      AgentGraph::ResearchGraph.new,
      AgentGraph::MemoWriteGraph.new,
      AgentGraph::MemoUpdateGraph.new
    ]

    assert_equal %w[research memo_write memo_update], graphs.map(&:name)
    assert_equal %w[plan_research plan_memo_write plan_memo_update], graphs.map(&:start_node)
    assert_equal [
      AgentGraph::ResearchStateSchema,
      AgentGraph::MemoWriteStateSchema,
      AgentGraph::MemoUpdateStateSchema
    ], graphs.map(&:state_schema)
  end

  test "memo write graph declares fixed edges" do
    graph = AgentGraph::MemoWriteGraph.new

    assert_equal "draft_memo", graph.next_node_for("plan_memo_write", {})
    assert_equal "await_approval", graph.next_node_for("draft_memo", {})
    assert_equal "commit_memo", graph.next_node_for("await_approval", {})
    assert_equal "finalize_reply", graph.next_node_for("commit_memo", {})
    assert_nil graph.next_node_for("finalize_reply", {})
  end

  test "memo update graph declares fixed edges" do
    graph = AgentGraph::MemoUpdateGraph.new

    assert_equal "draft_memo_update", graph.next_node_for("plan_memo_update", {})
    assert_equal "await_approval", graph.next_node_for("draft_memo_update", {})
    assert_equal "commit_memo_update", graph.next_node_for("await_approval", {})
    assert_equal "finalize_update_reply", graph.next_node_for("commit_memo_update", {})
    assert_nil graph.next_node_for("finalize_update_reply", {})
  end

  test "research graph declares routing edges" do
    graph = AgentGraph::ResearchGraph.new

    assert_equal "recall_memos", graph.next_node_for("plan_research", {
      "plan" => { "need_memo" => true, "need_web" => true }
    })
    assert_equal "search_web", graph.next_node_for("recall_memos", {
      "plan" => { "need_web" => true, "fetch_urls" => [] }
    })
    assert_equal "fetch_urls", graph.next_node_for("search_web", {
      "plan" => { "fetch_urls" => [ "https://example.com" ] }
    })
    assert_equal "synthesize_draft", graph.next_node_for("fetch_urls", {})
    assert_equal "finalize_answer", graph.next_node_for("synthesize_draft", {})
    assert_nil graph.next_node_for("finalize_answer", {})
  end

  test "missing edge is explicit failure" do
    error = assert_raises(RuntimeError) do
      AgentGraph::ResearchGraph.new.next_node_for("missing", {})
    end

    assert_includes error.message, "missing edge"
  end
end
