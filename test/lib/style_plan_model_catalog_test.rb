# frozen_string_literal: true

require "test_helper"

class StylePlanModelCatalogTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    AppSetting.delete_all
  end

  test "builds client from connection key" do
    client = StylePlanModelCatalog.client_for(connection_key: "llama_cpp")

    assert_instance_of LlamaCppClient, client
  end

  test "default_connection_key prefers config when enabled" do
    original = Rails.application.config.x.nyoy.style_plan_connection_key
    Rails.application.config.x.nyoy.style_plan_connection_key = "llama_cpp"

    assert_equal "llama_cpp", StylePlanModelCatalog.default_connection_key
  ensure
    Rails.application.config.x.nyoy.style_plan_connection_key = original
  end

  test "options_for_select lists enabled chat backends" do
    options = StylePlanModelCatalog.options_for_select

    assert options.any?
    assert_includes options.map(&:last), "llama_cpp"
  end
end
