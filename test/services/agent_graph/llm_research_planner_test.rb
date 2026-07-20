# frozen_string_literal: true

require "test_helper"

class AgentGraphLlmResearchPlannerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    @chat = Chat.create!(model: @model)
    AppSetting.delete_all
  end

  teardown do
    AppSetting.delete_all
  end

  test "uses light classification while preserving deterministic safety fields" do
    AppSetting.instance.update!(research_planner_model_id: @model.model_id)
    planner = AgentGraph::LlmResearchPlanner.new
    calls = []
    planner.define_singleton_method(:classify) do |model, question, chat|
      calls << { model: model, question: question, chat: chat }
      [
        { "need_web" => true, "need_memo" => false },
        { "cache_prompt" => true, "slot_id" => 2, "slot_count" => 4 },
        { "input_tokens" => 80, "output_tokens" => 12, "cached_tokens" => 60 }
      ]
    end

    plan, metadata = planner.call(
      state: { "question" => "https://example.com の仕様を確認してから保存して" },
      run: nil,
      chat: @chat
    )

    assert_equal true, plan["need_web"]
    assert_equal false, plan["need_memo"]
    assert_equal true, plan["sensitive"]
    assert_equal [ "https://example.com" ], plan["fetch_urls"]
    assert_equal "light", metadata["source"]
    assert_equal "gpt-oss", metadata["model_id"]
    assert_nil metadata["fallback"]
    assert_equal true, metadata.dig("llama_cache", "cache_prompt")
    assert_equal 2, metadata.dig("llama_cache", "slot_id")
    assert_equal 60, metadata.dig("usage", "cached_tokens")
    assert_equal 1, calls.size
    assert_equal "gpt-oss", calls.first.fetch(:model).model_id
    assert_equal "https://example.com の仕様を確認してから保存して", calls.first.fetch(:question)
    assert_same @chat, calls.first.fetch(:chat)
  end

  test "falls back to deterministic plan when model is not configured" do
    plan, metadata = AgentGraph::LlmResearchPlanner.new.call(
      state: { "question" => "最新情報を調べて" },
      run: nil,
      chat: @chat
    )

    assert_equal true, plan["need_web"]
    assert_equal "deterministic", metadata["source"]
    assert_equal "deterministic", metadata["fallback"]
    assert_includes metadata["error"], "not configured"
  end

  test "validates planner JSON boolean types" do
    planner = AgentGraph::LlmResearchPlanner.new
    parsed = planner.send(
      :parse_classification,
      '{"need_web":true,"need_memo":false}'
    )

    assert_equal({ "need_web" => true, "need_memo" => false }, parsed)
    assert_raises(ArgumentError) do
      planner.send(:parse_classification, '{"need_web":"yes","need_memo":false}')
    end
  end
end
