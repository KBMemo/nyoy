# frozen_string_literal: true

require "test_helper"

class LlmUsageAssignmentSeedsTest < ActiveSupport::TestCase
  setup do
    LlmUsageAssignment.delete_all
    ChatModelCatalog.seed!
  end

  test "seeds every usage from current settings and connections" do
    LlmUsageAssignmentSeeds.seed!

    assert_equal LlmUsageCatalog.keys.sort, LlmUsageAssignment.order(:usage_key).pluck(:usage_key).sort
    assert_equal "llama_cpp", connection_key_for("chat.default")
    assert_equal "vision_llama", connection_key_for("vision.image_understanding")
    assert_equal "embeddings", connection_key_for("embedding.memo_knowledge")
    assert_equal "llama_cpp", connection_key_for("utility.chat_history_summary")
  end

  test "uses configured agent model and records the chat model as fallback" do
    setting = AppSetting.instance
    setting.update!(research_draft_model_id: "gpt-oss")

    LlmUsageAssignmentSeeds.seed!

    assignment = LlmUsageAssignment.find_by!(usage_key: "agent.draft")
    assert_equal "gpt-oss", assignment.model.model_id
    assert_equal ServiceConnection.find_by!(key: "llama_cpp").server_model, assignment.fallback_model.model_id
  end

  test "preserves an existing assignment" do
    custom_model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    existing = LlmUsageAssignment.create!(usage_key: "chat.default", model: custom_model)

    LlmUsageAssignmentSeeds.seed!

    assert_equal existing.id, LlmUsageAssignment.find_by!(usage_key: "chat.default").id
    assert_equal custom_model, existing.reload.model
  end

  test "copies the current default sampling preset to chat assignment" do
    preset = LlmSamplingPreset.create!(key: "seed_test", name: "Seed test", params: { "temperature" => 0.2 })
    AppSetting.instance.update!(default_llm_sampling_preset_key: preset.key)

    LlmUsageAssignmentSeeds.seed!

    assert_equal preset, LlmUsageAssignment.find_by!(usage_key: "chat.default").llm_sampling_preset
  end

  private

  def connection_key_for(usage_key)
    LlmUsageAssignment.find_by!(usage_key: usage_key).model.metadata.fetch("connection_key")
  end
end
