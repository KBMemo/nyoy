# frozen_string_literal: true

require "test_helper"

class AgentGraphHybridLlmIntentRouterTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    @chat = Chat.create!(model: @model)
    AppSetting.delete_all
    LlmUsageAssignment.where(usage_key: "agent.intent").delete_all
    LlmUsageAssignment.create!(usage_key: "agent.intent", model: @model)
  end

  teardown do
    AppSetting.delete_all
    LlmUsageAssignment.where(usage_key: "agent.intent").delete_all
  end

  test "keeps deterministic graph decisions without calling the LLM" do
    router = AgentGraph::HybridLlmIntentRouter.new
    router.define_singleton_method(:classify) { |*| raise "LLM should not run" }

    result = router.call(chat: @chat, message: nil, text: "最新情報を調べて")

    assert_equal AgentGraph::ResearchGraph::NAME, result.fetch(:graph_name)
    assert_equal "strong", result.dig(:intent_decision, :reason)
  end

  test "escalates an unclassified external question to research" do
    router = AgentGraph::HybridLlmIntentRouter.new
    calls = []
    router.define_singleton_method(:classify) do |model, text, chat|
      calls << { model: model, text: text, chat: chat }
      [
        { "use_research_graph" => true },
        {
          "source" => "light",
          "model_id" => model.model_id,
          "usage" => { "input_tokens" => 50, "cached_tokens" => 30 }
        }
      ]
    end

    result = router.call(chat: @chat, message: nil, text: "Rails Active Job retry設計の要点は？")

    assert_equal AgentGraph::ResearchGraph::NAME, result.fetch(:graph_name)
    decision = result.fetch(:intent_decision)
    assert_equal "llm_research_escalation", decision.fetch(:reason)
    assert_equal "hybrid_llm", decision.fetch(:profile)
    assert_equal "gpt-oss", decision.fetch(:model_id)
    assert_equal 30, decision.dig(:usage, "cached_tokens")
    assert_equal 1, calls.size
    assert_equal @model, calls.first.fetch(:model)
    assert_equal "Rails Active Job retry設計の要点は？", calls.first.fetch(:text)
    assert_equal @chat, calls.first.fetch(:chat)
  end

  test "keeps ordinary chat outside AgentGraph" do
    router = AgentGraph::HybridLlmIntentRouter.new
    router.define_singleton_method(:classify) do |*|
      [ { "use_research_graph" => false }, {} ]
    end

    assert_nil router.call(chat: @chat, message: nil, text: "旅行の思い出を文章にして")
  end

  test "does not call LLM for an explicit non research turn" do
    router = AgentGraph::HybridLlmIntentRouter.new
    router.define_singleton_method(:classify) { |*| raise "LLM should not run" }

    assert_nil router.call(chat: @chat, message: nil, text: "こんにちは")
  end

  test "does not call LLM for an attachment turn left unclassified" do
    message = @chat.messages.create!(role: :user, content: "この画像を参考にイラストを作って")
    message.attachments.attach(io: StringIO.new("png"), filename: "pixel.png", content_type: "image/png")
    router = AgentGraph::HybridLlmIntentRouter.new
    router.define_singleton_method(:classify) { |*| raise "LLM should not run" }

    assert_nil router.call(chat: @chat, message: message, text: message.content)
  end

  test "rejects non boolean classification" do
    router = AgentGraph::HybridLlmIntentRouter.new

    assert_raises(ArgumentError) do
      router.send(:parse_classification, '{"use_research_graph":"yes"}')
    end
  end

  test "prompt treats changing software specifications as research" do
    assert_includes AgentGraph::HybridLlmIntentRouter::SYSTEM_PROMPT, "framework"
    assert_includes AgentGraph::HybridLlmIntentRouter::SYSTEM_PROMPT, "公式文書"
  end
end
