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

  test "json_schema_supported is false for gpt_oss" do
    assert StylePlanModelCatalog.json_schema_supported?("llama_cpp")
    assert_not StylePlanModelCatalog.json_schema_supported?("gpt_oss")
  end

  test "client_for passes api token for openai" do
    connection = service_connections(:openai)
    connection.update!(
      enabled: true,
      api_token: "sk-test-key",
      server_model: "gpt-4o-mini",
      settings: { "chat_models_catalog" => %w[gpt-4o-mini], "chat_models" => %w[gpt-4o-mini] }
    )

    client = StylePlanModelCatalog.client_for(connection_key: "openai")

    assert_equal "gpt-4o-mini", client.instance_variable_get(:@model)
    assert_equal "sk-test-key", client.instance_variable_get(:@api_token)
  end
end
