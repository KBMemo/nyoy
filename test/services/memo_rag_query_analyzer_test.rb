# frozen_string_literal: true

require "test_helper"

class MemoRagQueryAnalyzerTest < ActiveSupport::TestCase
  test "classifies simple queries" do
    analysis = MemoRagQueryAnalyzer.analyze("京都")

    assert_equal :simple, analysis.complexity
    assert_equal 3, analysis.top_k
  end

  test "classifies complex queries" do
    analysis = MemoRagQueryAnalyzer.analyze("徒然メモと Web 検索結果を比較して、旅行計画の違いをまとめて")

    assert_equal :complex, analysis.complexity
    assert_equal 10, analysis.top_k
  end

  test "extracts keywords" do
    analysis = MemoRagQueryAnalyzer.analyze("Rails pgvector の設定方法")

    assert_includes analysis.keywords, "rails"
    assert_includes analysis.keywords, "pgvector"
  end
end
