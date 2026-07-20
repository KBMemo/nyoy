# frozen_string_literal: true

require "test_helper"

class AgentGraphLlmEvidenceEvaluatorTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    @chat = Chat.create!(model: @model)
    AppSetting.delete_all
    AppSetting.instance.update!(evidence_evaluator_model_id: @model.model_id)
  end

  teardown do
    AppSetting.delete_all
  end

  test "keeps sufficient review when retrieved evidence supports the answer" do
    evaluator, calls = evaluator_with_classification(true)

    review, metadata = evaluator.call(state: reviewable_state, run: nil, chat: @chat)

    assert_equal "sufficient", review.fetch(:status)
    assert_equal "light", metadata.fetch("source")
    assert_equal "gpt-oss", metadata.fetch("model_id")
    assert_equal 25, metadata.dig("usage", "cached_tokens")
    assert_equal @model, calls.first.fetch(:model)
    assert_equal "question", calls.first.fetch(:state).fetch("question")
    assert_equal @chat, calls.first.fetch(:chat)
  end

  test "marks retrieved but insufficient evidence limited" do
    evaluator, = evaluator_with_classification(false)

    review, = evaluator.call(state: reviewable_state, run: nil, chat: @chat)

    assert_equal "limited", review.fetch(:status)
    assert_includes review.fetch(:reason), "does not sufficiently support"
  end

  test "does not call LLM while heuristic requests retrieval" do
    evaluator = AgentGraph::LlmEvidenceEvaluator.new
    evaluator.define_singleton_method(:classify) { |*| raise "LLM should not run" }
    state = reviewable_state.merge(
      "fetched_pages" => [],
      "plan" => { "need_web" => true },
      "budget" => { "searches_used" => 0, "max_searches" => 2, "fetches_used" => 0, "max_fetches" => 2 }
    )

    review, metadata = evaluator.call(state: state, run: nil, chat: @chat)

    assert_equal "needs_web", review.fetch(:status)
    assert_equal "heuristic", metadata.fetch("source")
    assert_nil metadata["fallback"]
  end

  test "falls back to heuristic review on classification failure" do
    evaluator = AgentGraph::LlmEvidenceEvaluator.new
    evaluator.define_singleton_method(:classify) { |*| raise "connection failed" }

    review, metadata = evaluator.call(state: reviewable_state, run: nil, chat: @chat)

    assert_equal "sufficient", review.fetch(:status)
    assert_equal "heuristic", metadata.fetch("source")
    assert_equal "heuristic", metadata.fetch("fallback")
    assert_equal "connection failed", metadata.fetch("error")
  end

  test "rejects a non boolean classification" do
    evaluator = AgentGraph::LlmEvidenceEvaluator.new

    assert_raises(ArgumentError) do
      evaluator.send(:parse_classification, '{"sufficient":"yes"}')
    end
  end

  test "limits serialized evidence size" do
    evaluator = AgentGraph::LlmEvidenceEvaluator.new
    state = reviewable_state.merge("memo_context" => "x" * 20_000)

    prompt = evaluator.send(:evidence_prompt, state)

    assert_operator prompt.length, :<=, AgentGraph::LlmEvidenceEvaluator::MAX_EVIDENCE_CHARS + 20
  end

  private

  def evaluator_with_classification(value)
    calls = []
    evaluator = AgentGraph::LlmEvidenceEvaluator.new.tap do |instance|
      instance.define_singleton_method(:classify) do |model, state, chat|
        calls << { model: model, state: state, chat: chat }
        [ value, { "cache_prompt" => true }, { "input_tokens" => 40, "cached_tokens" => 25 } ]
      end
    end
    [ evaluator, calls ]
  end

  def reviewable_state
    {
      "question" => "question",
      "plan" => { "need_web" => true },
      "memo_context" => nil,
      "search_results" => [],
      "fetched_pages" => [ { "url" => "https://example.com", "content_preview" => "answer evidence" } ],
      "evidence_review" => {},
      "budget" => { "searches_used" => 1, "max_searches" => 2, "fetches_used" => 1, "max_fetches" => 2 },
      "errors" => []
    }
  end
end
