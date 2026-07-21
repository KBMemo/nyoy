# frozen_string_literal: true

require "test_helper"

class ServiceConnectionLegacyKeyAuditTest < ActiveSupport::TestCase
  setup do
    @connection = service_connections(:llama_cpp)
    @connection.update!(
      key: "llama_server_test_main",
      legacy_key: "llama_cpp"
    )
  end

  test "reports legacy references by storage location" do
    AppSetting.instance.update_column(:default_chat_connection_key, "llama_cpp")
    model = Model.create!(
      provider: "openai",
      model_id: "legacy-audit-model",
      name: "Legacy audit model",
      capabilities: [ "chat" ],
      modalities: { "input" => [ "text" ], "output" => [ "text" ] },
      metadata: { "connection_key" => "llama_cpp" }
    )

    row = ServiceConnectionLegacyKeyAudit.call.find { |item| item.fetch("legacy_key") == "llama_cpp" }

    assert_equal 2, row.fetch("reference_count")
    assert_equal 1, row.dig("references", "app_settings.default_chat_connection_key")
    assert_equal 1, row.dig("references", "models.metadata.connection_key")
    assert_not row.fetch("database_clear")
  ensure
    model&.destroy!
  end

  test "marks connection clear when database only uses canonical key" do
    row = ServiceConnectionLegacyKeyAudit.call.find { |item| item.fetch("legacy_key") == "llama_cpp" }

    assert_equal({}, row.fetch("references"))
    assert row.fetch("database_clear")
  end
end
