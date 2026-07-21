# frozen_string_literal: true

require "test_helper"

class AppSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    AppSetting.delete_all
  end

  test "edit renders graph profile form without legacy model controls" do
    get edit_app_settings_path

    assert_response :success
    assert_select "input[type='radio'][name='app_setting[agent_graph_draft_profile]']", count: 3
    assert_select "select[name='app_setting[research_draft_fallback]']"
    assert_select "input[type='radio'][name='app_setting[agent_graph_planner_profile]']", count: 3
    assert_select "input[type='radio'][name='app_setting[agent_graph_evidence_evaluator_profile]']", count: 3
    assert_select "input[type='radio'][name='app_setting[agent_graph_final_answer_profile]']", count: 3
    assert_select "input[type='radio'][name='app_setting[agent_graph_intent_profile]']", count: 3
    assert_select "select[name='app_setting[default_chat_connection_key]']", count: 0
    assert_select "select[name='app_setting[research_draft_model_id]']", count: 0
  end

  test "update persists graph profiles only" do
    patch app_settings_path, params: {
      app_setting: {
        agent_graph_draft_profile: "llm",
        research_draft_fallback: "template",
        agent_graph_planner_profile: "llm",
        agent_graph_evidence_evaluator_profile: "llm",
        agent_graph_final_answer_profile: "light",
        agent_graph_intent_profile: "hybrid_llm",
        default_chat_connection_key: "gpt_oss",
        research_draft_model_id: "gpt-oss"
      }
    }

    assert_redirected_to edit_app_settings_path
    setting = AppSetting.instance
    assert_equal({
      "draft" => "llm",
      "planner" => "llm",
      "evidence_evaluator" => "llm",
      "final_answer" => "light",
      "intent" => "hybrid_llm"
    }, setting.agent_graph_role_profiles)
    assert_equal "template", setting.research_draft_fallback
    assert_not setting.has_attribute?(:default_chat_connection_key)
    assert_not setting.has_attribute?(:research_draft_model_id)
  end
end
