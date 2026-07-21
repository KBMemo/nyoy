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
    generation = ImageGeneration.create!(
      japanese_prompt: "legacy audit",
      sd_model: "flat2d",
      loras: "[]"
    )
    generation.update_column(:style_plan_connection_key, "llama_cpp")
    row = ServiceConnectionLegacyKeyAudit.call.find { |item| item.fetch("legacy_key") == "llama_cpp" }

    assert_equal 1, row.fetch("reference_count")
    assert_equal 1, row.dig("references", "image_generations.style_plan_connection_key")
    assert_not row.fetch("database_clear")
  ensure
    generation&.destroy!
  end

  test "marks connection clear when database only uses canonical key" do
    row = ServiceConnectionLegacyKeyAudit.call.find { |item| item.fetch("legacy_key") == "llama_cpp" }

    assert_equal({}, row.fetch("references"))
    assert row.fetch("database_clear")
  end
end
