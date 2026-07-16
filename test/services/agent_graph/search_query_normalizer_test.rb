# frozen_string_literal: true

require "test_helper"

class AgentGraphSearchQueryNormalizerTest < ActiveSupport::TestCase
  test "strips research fillers into keyword query" do
    queries = AgentGraph::SearchQueryNormalizer.queries_for(
      "高尾山から景信山への登山道を調べて 出典 根拠"
    )

    assert_equal "高尾山 景信山 登山道", queries.first
    assert_includes queries, "高尾山 景信山 登山ルート"
    queries.each do |query|
      refute_includes query, "調べて"
      refute_includes query, "出典"
      refute_includes query, "根拠"
    end
  end

  test "keeps english product names and drops please verbs" do
    queries = AgentGraph::SearchQueryNormalizer.queries_for(
      "Hydrangea Rin の公式情報を調べてください"
    )

    assert_equal "Hydrangea Rin 公式情報", queries.first
  end

  test "falls back when question is only fillers" do
    queries = AgentGraph::SearchQueryNormalizer.queries_for("調べて 出典")

    assert queries.first.present?
  end
end
