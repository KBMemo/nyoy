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
      "errors" => [],
      "rejection_notes" => [],
      "replan_count" => 0
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
end
