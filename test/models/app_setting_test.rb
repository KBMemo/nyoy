# frozen_string_literal: true

require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  setup do
    AppSetting.delete_all
    LlmUsageAssignment.delete_all
    LlmSamplingPresetSeeds.seed!
    LlmUsageAssignmentSeeds.seed!
  end

  test "resolves models and connections from usage assignments" do
    chat = LlmUsageAssignment.find_by!(usage_key: "chat.default")
    draft = LlmUsageAssignment.find_by!(usage_key: "agent.draft")
    style = LlmUsageAssignment.find_by!(usage_key: "image.style_plan")

    assert_equal chat.model, ChatModelCatalog.default_model
    assert_equal chat.model.metadata["connection_key"], AppSetting.default_chat_connection_key
    assert_equal draft.model, AppSetting.research_draft_model
    assert_equal style.model.metadata["connection_key"], AppSetting.default_style_plan_connection_key
  end

  test "resolves default sampling from chat usage assignment" do
    preset = LlmSamplingPreset.enabled.find_by!(key: "qwen3_5_9b")
    LlmUsageAssignment.find_by!(usage_key: "chat.default").update!(llm_sampling_preset: preset)

    params = AppSetting.default_chat_llm_params

    assert_in_delta 0.7, params["temperature"]
    assert_in_delta 0.8, params["top_p"]
  end

  test "stores draft role profile through virtual attribute" do
    setting = AppSetting.instance
    setting.agent_graph_draft_profile = "llm"
    setting.save!

    assert_equal "llm", setting.reload.agent_graph_draft_profile
    assert_equal({ "draft" => "llm" }, setting.agent_graph_role_profiles)
  end

  test "clears draft role profile without removing other roles" do
    setting = AppSetting.instance
    setting.update!(agent_graph_role_profiles: { "draft" => "llm", "intent" => "deterministic" })

    setting.update!(agent_graph_draft_profile: "")

    assert_nil setting.agent_graph_draft_profile
    assert_equal({ "intent" => "deterministic" }, setting.agent_graph_role_profiles)
  end

  test "rejects unknown role profile" do
    setting = AppSetting.new(agent_graph_role_profiles: { "draft" => "missing" })

    assert_not setting.valid?
    assert_includes setting.errors[:agent_graph_role_profiles], "draft.missing は登録されていません"
  end
end
