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

  test "seeds agent usages from the default chat model" do
    LlmUsageAssignmentSeeds.seed!

    chat = LlmUsageAssignment.find_by!(usage_key: "chat.default")
    assignment = LlmUsageAssignment.find_by!(usage_key: "agent.draft")
    assert_equal chat.model, assignment.model
    assert_nil assignment.fallback_model
  end

  test "preserves an existing assignment" do
    custom_model = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    existing = LlmUsageAssignment.create!(usage_key: "chat.default", model: custom_model)

    LlmUsageAssignmentSeeds.seed!

    assert_equal existing.id, LlmUsageAssignment.find_by!(usage_key: "chat.default").id
    assert_equal custom_model, existing.reload.model
  end

  private

  def connection_key_for(usage_key)
    LlmUsageAssignment.find_by!(usage_key: usage_key).model.service_connection.key
  end
end
