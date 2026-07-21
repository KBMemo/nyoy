# frozen_string_literal: true

require "test_helper"

class LlmUsageAssignmentTest < ActiveSupport::TestCase
  test "accepts a model with all required capabilities" do
    assignment = LlmUsageAssignment.new(usage_key: "chat.default", model: text_model)

    assert assignment.valid?
    assert_equal "通常Chat", assignment.definition.label
  end

  test "rejects unknown and duplicate usage keys" do
    LlmUsageAssignment.create!(usage_key: "agent.draft", model: text_model)

    duplicate = LlmUsageAssignment.new(usage_key: "agent.draft", model: another_text_model)
    unknown = LlmUsageAssignment.new(usage_key: "unknown", model: text_model)

    assert_not duplicate.valid?
    assert_not unknown.valid?
    assert duplicate.errors[:usage_key].any?
    assert unknown.errors[:usage_key].any?
  end

  test "rejects models missing required capabilities" do
    assignment = LlmUsageAssignment.new(usage_key: "vision.image_understanding", model: text_model)

    assert_not assignment.valid?
    assert_match "vision", assignment.errors[:model].to_sentence
  end

  test "accepts vision and embedding models for matching usages" do
    vision_assignment = LlmUsageAssignment.new(usage_key: "vision.image_understanding", model: vision_model)
    embedding_assignment = LlmUsageAssignment.new(usage_key: "embedding.memo_knowledge", model: embedding_model)

    assert vision_assignment.valid?
    assert embedding_assignment.valid?
  end

  test "validates fallback model capabilities and identity" do
    missing_capability = LlmUsageAssignment.new(
      usage_key: "embedding.memo_knowledge",
      model: embedding_model,
      fallback_model: text_model
    )
    same_model = LlmUsageAssignment.new(
      usage_key: "agent.final_answer",
      model: text_model,
      fallback_model: text_model
    )

    assert_not missing_capability.valid?
    assert_match "embedding", missing_capability.errors[:fallback_model].to_sentence
    assert_not same_model.valid?
    assert_includes same_model.errors[:fallback_model], "は主モデルと異なるモデルを選択してください"
  end

  private

  def text_model
    @text_model ||= create_model("text-model", capabilities: [ "chat" ])
  end

  def another_text_model
    @another_text_model ||= create_model("other-text-model", capabilities: [ "chat" ])
  end

  def vision_model
    @vision_model ||= create_model(
      "vision-model",
      capabilities: [ "chat" ],
      modalities: { "input" => %w[text image], "output" => [ "text" ] }
    )
  end

  def embedding_model
    @embedding_model ||= create_model("embedding-model", capabilities: [ "embedding" ])
  end

  def create_model(model_id, capabilities:, modalities: {})
    Model.create!(
      provider: "openai",
      model_id: model_id,
      name: model_id,
      capabilities: capabilities,
      modalities: modalities
    )
  end
end
