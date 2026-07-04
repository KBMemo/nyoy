# frozen_string_literal: true

require "test_helper"

class AppSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ChatModelCatalog.seed!
    AppSetting.delete_all
  end

  test "edit renders defaults form" do
    get edit_app_settings_path

    assert_response :success
    assert_select "select[name='app_setting[default_chat_connection_key]']"
    assert_select "select[name='app_setting[default_style_plan_connection_key]']"
  end

  test "update persists defaults" do
    patch app_settings_path, params: {
      app_setting: {
        default_chat_connection_key: "gpt_oss",
        default_style_plan_connection_key: "gpt_oss"
      }
    }

    assert_redirected_to edit_app_settings_path
    setting = AppSetting.instance
    assert_equal "gpt_oss", setting.default_chat_connection_key
    assert_equal "gpt_oss", setting.default_style_plan_connection_key
    assert_equal "gpt_oss", AppSetting.default_chat_connection_key
    assert_equal "gpt_oss", StylePlanModelCatalog.default_connection_key
  end

  test "update can clear defaults to use env fallback" do
    AppSetting.instance.update!(
      default_chat_connection_key: "gpt_oss",
      default_style_plan_connection_key: "gpt_oss"
    )

    patch app_settings_path, params: {
      app_setting: {
        default_chat_connection_key: "",
        default_style_plan_connection_key: ""
      }
    }

    assert_redirected_to edit_app_settings_path
    setting = AppSetting.instance
    assert_nil setting.default_chat_connection_key
    assert_nil setting.default_style_plan_connection_key
  end
end
