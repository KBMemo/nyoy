# frozen_string_literal: true

require "test_helper"

class AgentGraphFinalAnswerSynthesizerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @state = {
      "question" => "高尾山の登山ルートは？",
      "draft" => "短いドラフト回答\n\n---\n\n### 出典\n- https://example.com",
      "memo_context" => nil,
      "search_results" => [],
      "fetched_pages" => [],
      "errors" => []
    }
  end

  test "passthrough returns approved draft" do
    previous = AgentGraph::FinalAnswerSynthesizer.force_passthrough
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = true

    answer, truncated, meta = AgentGraph::FinalAnswerSynthesizer.new(@chat).call(@state)

    assert_equal @state["draft"], answer
    assert_equal false, truncated
    assert_equal "draft", meta["source"]
  ensure
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = previous
  end

  test "llm failure returns nil so the run can surface a chat error" do
    synthesizer = AgentGraph::FinalAnswerSynthesizer.new(@chat)
    synthesizer.define_singleton_method(:ask_main_model) do |_evidence|
      [ nil, false, { "error" => "Faraday::ConnectionFailed: Connection refused", "model_id" => "gpt-oss" } ]
    end

    answer, _truncated, meta = synthesizer.call(@state)

    assert_nil answer
    assert_equal "error", meta["source"]
    assert_includes meta["error"], "Connection refused"
  end

  test "final prompt delegates source list rendering to the system" do
    system = AgentGraph::FinalAnswerSynthesizer::FINAL_SYSTEM
    prompt = AgentGraph::FinalAnswerSynthesizer.new(@chat).send(
      :user_prompt,
      {
        question: "出典は？",
        memo: nil,
        search_results: [],
        fetched_pages: [],
        evidence_review: {},
        errors: []
      }
    )

    assert_includes system, "URL・出典リスト・「調査結果」見出しは付けない"
    assert_includes prompt, "URL・出典リスト・「調査結果」見出しは付けない"
    assert_includes system, "追加の検索やページ取得が必要"
    assert_includes prompt, "追加検索やページ取得が必要"
    assert_no_match(/文末に関連 URL/, system)
    assert_no_match(/だけを根拠/, system)
  end

  test "final prompt asks for next research suggestions when evidence is limited" do
    prompt = AgentGraph::FinalAnswerSynthesizer.new(@chat).send(
      :user_prompt,
      {
        question: "最新の仕様は？",
        memo: nil,
        search_results: [],
        fetched_pages: [],
        plan: {
          "queries" => [ "仕様 2026", "公式 changelog", "移行ガイド" ],
          "searched_queries" => [ "仕様 2026" ],
          "fetch_urls" => [ "https://example.com/spec" ]
        },
        evidence_review: {
          "status" => "limited",
          "reason" => "available evidence is limited and no additional retrieval is available"
        },
        budget: { "fetched_urls" => [] },
        errors: []
      }
    )

    assert_includes AgentGraph::FinalAnswerSynthesizer::FINAL_SYSTEM, "次に試す検索語"
    assert_includes prompt, "証拠評価: status=limited"
    assert_includes prompt, "次に試す検索語"
    assert_includes prompt, "ユーザーに確認したい条件"
    assert_includes prompt, "追加調査候補:"
    assert_includes prompt, "検索: 公式 changelog"
    assert_includes prompt, "ページ取得: https://example.com/spec"
  end
end
