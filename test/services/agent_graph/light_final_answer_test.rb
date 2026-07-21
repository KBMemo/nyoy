# frozen_string_literal: true

require "test_helper"

class AgentGraphLightFinalAnswerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @main_model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    @light_model = @main_model
    @chat = Chat.create!(model: @main_model)
    @state = { "question" => "question", "draft" => "draft" }
    AppSetting.delete_all
    LlmUsageAssignment.where(usage_key: "agent.final_answer").delete_all
    LlmUsageAssignment.create!(usage_key: "agent.final_answer", model: @light_model)
  end

  teardown do
    AppSetting.delete_all
    LlmUsageAssignment.where(usage_key: "agent.final_answer").delete_all
  end

  test "uses configured light model and dedicated cache slot" do
    calls = []
    synthesizer_class = fake_synthesizer_class(calls, [ "light answer", false, { "source" => "light" } ])
    fallback = Object.new
    fallback.define_singleton_method(:call) { |**| raise "main fallback should not run" }
    service = AgentGraph::RoleServices::LightFinalAnswer.new(
      fallback: fallback,
      synthesizer_class: synthesizer_class
    )

    answer, truncated, metadata = service.call(state: @state, run: :run, chat: @chat)

    assert_equal "light answer", answer
    assert_equal false, truncated
    assert_equal "light", metadata.fetch("source")
    assert_equal 1, calls.size
    assert_equal @chat, calls.first.dig(:options, :chat)
    assert_equal @light_model, calls.first.dig(:options, :model)
    assert_equal "light", calls.first.dig(:options, :source)
    assert_equal(
      "agent_graph:final_light:#{@chat.id}:#{@light_model.model_id}",
      calls.first.dig(:options, :cache_slot_key)
    )
    assert_equal @state, calls.first.fetch(:state)
  end

  test "falls back to main when light synthesis fails" do
    synthesizer_class = fake_synthesizer_class([], [ nil, false, { "source" => "error", "error" => "light failed" } ])
    fallback = fallback_service
    service = AgentGraph::RoleServices::LightFinalAnswer.new(
      fallback: fallback,
      synthesizer_class: synthesizer_class
    )

    answer, truncated, metadata = service.call(state: @state, run: :run, chat: @chat)

    assert_equal "main answer", answer
    assert_equal false, truncated
    assert_equal "main", metadata.fetch("source")
    assert_equal "main", metadata.fetch("fallback")
    assert_equal "light failed", metadata.fetch("fallback_error")
    assert_equal @light_model.model_id, metadata.fetch("light_model_id")
  end

  test "calls main fallback once when light synthesizer raises" do
    synthesizer_class = Class.new do
      define_singleton_method(:new) { |*| raise "light connection failed" }
    end
    fallback_calls = []
    fallback = Object.new
    fallback.define_singleton_method(:call) do |**kwargs|
      fallback_calls << kwargs
      [ "main answer", false, { "source" => "main" } ]
    end
    service = AgentGraph::RoleServices::LightFinalAnswer.new(
      fallback: fallback,
      synthesizer_class: synthesizer_class
    )

    answer, _truncated, metadata = service.call(state: @state, run: :run, chat: @chat)

    assert_equal "main answer", answer
    assert_equal "main", metadata.fetch("fallback")
    assert_equal "light connection failed", metadata.fetch("fallback_error")
    assert_equal 1, fallback_calls.size
  end

  test "falls back to main when light model is not configured" do
    LlmUsageAssignment.find_by!(usage_key: "agent.final_answer").destroy!
    service = AgentGraph::RoleServices::LightFinalAnswer.new(
      fallback: fallback_service,
      synthesizer_class: fake_synthesizer_class([], nil)
    )

    answer, _truncated, metadata = service.call(state: @state, run: :run, chat: @chat)

    assert_equal "main answer", answer
    assert_equal "main", metadata.fetch("fallback")
    assert_equal "final answer model is not configured", metadata.fetch("fallback_error")
    assert_nil metadata["light_model_id"]
  end

  private

  def fake_synthesizer_class(calls, result)
    Class.new do
      define_singleton_method(:new) do |chat, **options|
        instance = Object.new
        instance.define_singleton_method(:call) do |state|
          calls << { options: options.merge(chat: chat), state: state }
          result
        end
        instance
      end
    end
  end

  def fallback_service
    Object.new.tap do |service|
      service.define_singleton_method(:call) do |state:, run:, chat:|
        [ "main answer", false, { "source" => "main", "model_id" => chat.model_association.model_id } ]
      end
    end
  end
end
