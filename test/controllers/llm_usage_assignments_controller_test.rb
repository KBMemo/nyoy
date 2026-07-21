# frozen_string_literal: true

require "test_helper"

class LlmUsageAssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ChatModelCatalog.seed!
    LlmSamplingPresetSeeds.seed!
    LlmUsageAssignment.delete_all
    LlmUsageAssignmentSeeds.seed!
  end

  test "index renders every seeded usage assignment" do
    get llm_usage_assignments_path

    assert_response :success
    assert_select "article[id^='llm_usage_assignment_']", count: LlmUsageCatalog.keys.size
    assert_select "select[name='llm_usage_assignment[model_id]']", count: LlmUsageCatalog.keys.size
    assert_select "select[name='llm_usage_assignment[fallback_model_id]']", count: LlmUsageCatalog.keys.size
    generation_usage_count = LlmUsageCatalog.all.count { |definition| definition.capabilities.include?(:text_generation) }
    assert_select "select[name='llm_usage_assignment[llm_sampling_preset_id]']", count: generation_usage_count
  end

  test "index reports missing usages without creating assignments" do
    missing = LlmUsageAssignment.find_by!(usage_key: "agent.draft")
    missing.destroy!

    assert_no_difference("LlmUsageAssignment.count") do
      get llm_usage_assignments_path
    end

    assert_response :success
    assert_select ".kb-alert-warning", text: /モデルを解決できない用途が1件あります/
    assert_nil LlmUsageAssignment.find_by(usage_key: "agent.draft")
  end

  test "update changes model fallback preset and enabled state" do
    assignment = LlmUsageAssignment.find_by!(usage_key: "agent.draft")
    candidates = Model.all.select do |model|
      (assignment.definition.capabilities - LlmModelCapabilities.for(model)).empty?
    end
    primary, fallback = candidates.first(2)
    preset = LlmSamplingPreset.enabled.first!

    patch llm_usage_assignment_path(assignment), params: {
      llm_usage_assignment: {
        model_id: primary.id,
        fallback_model_id: fallback.id,
        llm_sampling_preset_id: preset.id,
        enabled: "0"
      }
    }

    assert_redirected_to llm_usage_assignments_path(anchor: "llm_usage_assignment_#{assignment.id}")
    assignment.reload
    assert_equal primary, assignment.model
    assert_equal fallback, assignment.fallback_model
    assert_equal preset, assignment.llm_sampling_preset
    assert_not assignment.enabled?
  end

  test "update rejects a model without required capabilities" do
    assignment = LlmUsageAssignment.find_by!(usage_key: "vision.image_understanding")
    text_model = Model.all.find { |model| !LlmModelCapabilities.for(model).include?(:vision) }

    patch llm_usage_assignment_path(assignment), params: {
      llm_usage_assignment: { model_id: text_model.id, enabled: "1" }
    }

    assert_response :unprocessable_entity
    assert_select "[role='alert']", text: /必要な能力を満たしていません/
    assert_equal "vision.image_understanding", assignment.reload.usage_key
  end

  test "update rejects a sampling preset for an embedding usage" do
    assignment = LlmUsageAssignment.find_by!(usage_key: "embedding.memo_knowledge")
    preset = LlmSamplingPreset.enabled.first!

    patch llm_usage_assignment_path(assignment), params: {
      llm_usage_assignment: { llm_sampling_preset_id: preset.id, enabled: "1" }
    }

    assert_response :unprocessable_entity
    assert_select "[role='alert']", text: /テキスト生成用途にだけ設定できます/
    assert_nil assignment.reload.llm_sampling_preset
  end
end
