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

  test "parses model list from switchd stdout" do
    client = FakeSwitchClient.new(
      configured: true,
      models_response: { "stdout" => "flat2d\nanythingv5\ndreamshaper8\n" },
      current_response: { "stdout" => "flat2d\n" }
    )

    catalog = SdModelCatalog.new(switch_client: client)

    assert_equal %w[flat2d anythingv5 dreamshaper8], catalog.model_names
    assert_equal "flat2d", catalog.current_model
  end
end
