# frozen_string_literal: true

require "test_helper"

class SdModelCatalogTest < ActiveSupport::TestCase
  FakeSwitchClient = Struct.new(:configured, :models_response, :current_response, keyword_init: true) do
    def configured?
      configured
    end

    def models
      models_response
    end

    def current
      current_response
    end
  end

  test "parses model list from switchd models array" do
    client = FakeSwitchClient.new(
      configured: true,
      models_response: {
        "ok" => true,
        "models" => %w[flat2d anythingv5 dreamshaper8 pony-v6]
      },
      current_response: {
        "ok" => true,
        "model" => "pony-v6"
      }
    )

    catalog = SdModelCatalog.new(switch_client: client)

    assert_equal %w[flat2d anythingv5 dreamshaper8 pony-v6], catalog.model_names
    assert_equal "pony-v6", catalog.current_model
  end

  test "parses model list from legacy switchd stdout" do
    client = FakeSwitchClient.new(
      configured: true,
      models_response: { "stdout" => "flat2d\nanythingv5\ndreamshaper8\npony-v6\n" },
      current_response: { "stdout" => "flat2d\n" }
    )

    catalog = SdModelCatalog.new(switch_client: client)

    assert_equal %w[flat2d anythingv5 dreamshaper8 pony-v6], catalog.model_names
    assert_equal "flat2d", catalog.current_model
  end

  test "raises when switchd is configured but models are unavailable" do
    client = FakeSwitchClient.new(
      configured: true,
      models_response: { "ok" => true, "models" => [] },
      current_response: { "ok" => true, "model" => "flat2d" }
    )

    catalog = SdModelCatalog.new(switch_client: client)

    assert_raises(SdModelCatalog::Unavailable) do
      catalog.model_names
    end
  end

  test "uses fallback models only when switchd is not configured" do
    catalog = SdModelCatalog.new(
      switch_client: FakeSwitchClient.new(configured: false)
    )

    assert_equal Rails.application.config.x.nyoy.default_sd_models, catalog.model_names
    assert_not catalog.configured?
  end

  test "returns pony-v6 default lora from config" do
    catalog = SdModelCatalog.new(
      switch_client: FakeSwitchClient.new(configured: false)
    )

    assert_equal ["ChojuGiga_Illustrious"], catalog.loras_for("pony-v6")
    assert_equal "ChojuGiga_Illustrious", catalog.default_lora_for("pony-v6")
    assert_empty catalog.loras_for("flat2d")
  end
end
