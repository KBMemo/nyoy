# frozen_string_literal: true

require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  setup do
    AppSetting.delete_all
    LlmUsageAssignment.delete_all
    LlmSamplingPresetSeeds.seed!
    LlmUsageAssignmentSeeds.seed!
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
