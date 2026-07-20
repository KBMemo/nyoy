# frozen_string_literal: true

require "test_helper"

class AppSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ChatModelCatalog.seed!
    AppSetting.delete_all
  end

  test "edit renders defaults form" do
    LlmSamplingPresetSeeds.seed!
    get edit_app_settings_path

    assert_response :success
    assert_select "select[name='app_setting[default_chat_connection_key]']"
    assert_select "select[name='app_setting[default_style_plan_connection_key]']"
    assert_select "select[name='app_setting[default_llm_sampling_preset_key]']"
    assert_select "input[type='radio'][name='app_setting[agent_graph_draft_profile]']", count: 3
    assert_select "select[name='app_setting[research_draft_model_id]']"
    assert_select "select[name='app_setting[research_draft_fallback]']"
    assert_select "input[type='radio'][name='app_setting[agent_graph_planner_profile]']", count: 3
    assert_select "select[name='app_setting[research_planner_model_id]']"
  end

  test "update persists defaults" do
    LlmSamplingPresetSeeds.seed!
    patch app_settings_path, params: {
      app_setting: {
        default_chat_connection_key: "gpt_oss",
        default_style_plan_connection_key: "gpt_oss",
        default_llm_sampling_preset_key: "qwen3_5_9b",
        agent_graph_draft_profile: "llm",
        research_draft_model_id: "gpt-oss",
        research_draft_fallback: "template",
        agent_graph_planner_profile: "llm",
        research_planner_model_id: "gpt-oss"
      }
    }

    assert_redirected_to edit_app_settings_path
    setting = AppSetting.instance
    assert_equal "gpt_oss", setting.default_chat_connection_key
    assert_equal "gpt_oss", setting.default_style_plan_connection_key
    assert_equal "qwen3_5_9b", setting.default_llm_sampling_preset_key
    assert_equal "llm", setting.agent_graph_draft_profile
    assert_equal({ "draft" => "llm", "planner" => "llm" }, setting.agent_graph_role_profiles)
    assert_equal "gpt-oss", setting.research_draft_model_id
    assert_equal "template", setting.research_draft_fallback
    assert_equal "llm", setting.agent_graph_planner_profile
    assert_equal "gpt-oss", setting.research_planner_model_id
    assert_equal "gpt_oss", AppSetting.default_chat_connection_key
    assert_equal "gpt_oss", StylePlanModelCatalog.default_connection_key
    assert_in_delta 0.7, AppSetting.default_chat_llm_params["temperature"]
    assert_equal "gpt-oss", AppSetting.research_draft_model.model_id
    assert_equal "template", AppSetting.research_draft_fallback
  end

  test "update can clear defaults to use env fallback" do
    LlmSamplingPresetSeeds.seed!
    AppSetting.instance.update!(
      default_chat_connection_key: "gpt_oss",
      default_style_plan_connection_key: "gpt_oss",
      default_llm_sampling_preset_key: "qwen3_5_9b",
      agent_graph_role_profiles: { "draft" => "llm", "planner" => "llm" },
      research_draft_model_id: "gpt-oss",
      research_draft_fallback: "template",
      research_planner_model_id: "gpt-oss"
    )

    patch app_settings_path, params: {
      app_setting: {
        default_chat_connection_key: "",
        default_style_plan_connection_key: "",
        default_llm_sampling_preset_key: "",
        agent_graph_draft_profile: "",
        research_draft_model_id: "",
        research_draft_fallback: "",
        research_planner_model_id: "",
        agent_graph_planner_profile: ""
      }
    }

    assert_redirected_to edit_app_settings_path
    setting = AppSetting.instance
    assert_nil setting.default_chat_connection_key
    assert_nil setting.default_style_plan_connection_key
    assert_nil setting.default_llm_sampling_preset_key
    assert_nil setting.agent_graph_draft_profile
    assert_equal({}, setting.agent_graph_role_profiles)
    assert_nil setting.research_draft_model_id
    assert_nil setting.research_planner_model_id
    assert_equal "main", setting.research_draft_fallback
    assert_equal({}, AppSetting.default_chat_llm_params)
    assert_nil AppSetting.research_draft_model
  end
end
