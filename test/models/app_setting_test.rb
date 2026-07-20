# frozen_string_literal: true

require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    AppSetting.delete_all
    @original_chat = Rails.application.config.x.nyoy.default_chat_connection_key
    @original_style = Rails.application.config.x.nyoy.style_plan_connection_key
    Rails.application.config.x.nyoy.default_chat_connection_key = "llama_cpp"
    Rails.application.config.x.nyoy.style_plan_connection_key = "llama_cpp"
  end

  teardown do
    Rails.application.config.x.nyoy.default_chat_connection_key = @original_chat
    Rails.application.config.x.nyoy.style_plan_connection_key = @original_style
    AppSetting.delete_all
  end

  test "falls back to env config when unset" do
    assert_equal "llama_cpp", AppSetting.default_chat_connection_key
    assert_equal "llama_cpp", AppSetting.default_style_plan_connection_key
  end

  test "prefers stored values when available" do
    AppSetting.instance.update!(
      default_chat_connection_key: "gpt_oss",
      default_style_plan_connection_key: "gpt_oss"
    )

    assert_equal "gpt_oss", AppSetting.default_chat_connection_key
    assert_equal "gpt_oss", AppSetting.default_style_plan_connection_key
  end

  test "rejects unknown connection keys" do
    setting = AppSetting.instance
    setting.default_chat_connection_key = "missing_backend"

    assert_not setting.valid?
    assert_includes setting.errors[:default_chat_connection_key], "は有効な接続を選んでください"
  end

  test "default_chat_llm_params resolves enabled sampling preset" do
    LlmSamplingPresetSeeds.seed!
    AppSetting.instance.update!(default_llm_sampling_preset_key: "qwen3_5_9b")

    params = AppSetting.default_chat_llm_params

    assert_in_delta 0.7, params["temperature"]
    assert_in_delta 0.8, params["top_p"]
    assert_nil params["enable_thinking"]
  end

  test "default_chat_llm_params is empty when unset" do
    assert_equal({}, AppSetting.default_chat_llm_params)
  end

  test "rejects unknown sampling preset keys" do
    setting = AppSetting.instance
    setting.default_llm_sampling_preset_key = "missing_preset"

    assert_not setting.valid?
    assert_includes setting.errors[:default_llm_sampling_preset_key], "は有効なサンプリングプリセットを選んでください"
  end

  test "research_draft_model resolves stored model_id" do
    AppSetting.instance.update!(research_draft_model_id: "gpt-oss")

    assert_equal "gpt-oss", AppSetting.research_draft_model.model_id
  end

  test "rejects unknown research draft model" do
    setting = AppSetting.instance
    setting.research_draft_model_id = "missing-model"

    assert_not setting.valid?
    assert_includes setting.errors[:research_draft_model_id], "は有効なチャットモデルを選んでください"
  end

  test "research planner model and profile are independently configurable" do
    setting = AppSetting.instance
    setting.update!(research_planner_model_id: "gpt-oss", agent_graph_planner_profile: "llm")

    assert_equal "gpt-oss", AppSetting.research_planner_model.model_id
    assert_equal "llm", setting.reload.agent_graph_planner_profile
    assert_equal({ "planner" => "llm" }, setting.agent_graph_role_profiles)
  end

  test "rejects unknown research planner model" do
    setting = AppSetting.instance
    setting.research_planner_model_id = "missing-model"

    assert_not setting.valid?
    assert_includes setting.errors[:research_planner_model_id], "は有効なチャットモデルを選んでください"
  end

  test "stores draft role profile through virtual attribute" do
    setting = AppSetting.instance
    setting.agent_graph_draft_profile = "llm"
    setting.save!

    assert_equal "llm", setting.reload.agent_graph_draft_profile
    assert_equal({ "draft" => "llm" }, setting.agent_graph_role_profiles)
  end

  test "clears draft role profile without removing other roles" do
    setting = AppSetting.create!(agent_graph_role_profiles: {
      "draft" => "llm",
      "intent" => "deterministic"
    })

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
