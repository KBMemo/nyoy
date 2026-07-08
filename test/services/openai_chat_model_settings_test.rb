# frozen_string_literal: true

require "test_helper"

class OpenaiChatModelSettingsTest < ActiveSupport::TestCase
  test "from uses chat_models as catalog when catalog key is missing" do
    settings = OpenaiChatModelSettings.from("chat_models" => %w[gpt-4o gpt-4o-mini])

    assert_equal %w[gpt-4o gpt-4o-mini], settings.catalog
    assert_equal %w[gpt-4o gpt-4o-mini], settings.enabled
  end

  test "normalize keeps enabled models within catalog" do
    result = OpenaiChatModelSettings.normalize(
      catalog: %w[gpt-4o gpt-4o-mini gpt-3.5-turbo],
      enabled: { "gpt-4o" => "1", "gpt-3.5-turbo" => "0" }
    )

    assert_equal %w[gpt-3.5-turbo gpt-4o gpt-4o-mini], result["chat_models_catalog"]
    assert_equal %w[gpt-4o], result["chat_models"]
  end

  test "merge_catalog preserves enabled models and auto-enables new models" do
    current = {
      "chat_models_catalog" => %w[gpt-4o gpt-4o-mini],
      "chat_models" => %w[gpt-4o]
    }

    merged = OpenaiChatModelSettings.merge_catalog(current, %w[gpt-4o gpt-4o-mini gpt-3.5-turbo])

    assert_equal %w[gpt-3.5-turbo gpt-4o gpt-4o-mini], merged["chat_models_catalog"]
    assert_equal %w[gpt-3.5-turbo gpt-4o], merged["chat_models"]
  end

  test "grouped_catalog groups dated model variants" do
    settings = OpenaiChatModelSettings.from(
      "chat_models_catalog" => %w[gpt-3.5-turbo gpt-3.5-turbo-0125 gpt-4o],
      "chat_models" => %w[gpt-3.5-turbo gpt-4o]
    )

    groups = settings.grouped_catalog.to_h

    assert_equal %w[gpt-3.5-turbo gpt-3.5-turbo-0125], groups["gpt-3.5-turbo"]
    assert_equal %w[gpt-4o], groups["gpt-4o"]
  end
end
