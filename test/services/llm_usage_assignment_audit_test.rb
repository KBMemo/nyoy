# frozen_string_literal: true

require "test_helper"

class LlmUsageAssignmentAuditTest < ActiveSupport::TestCase
  setup do
    LlmUsageAssignment.delete_all
    LlmUsageAssignmentSeeds.seed!
  end

  test "reports all seeded usages as healthy" do
    rows = LlmUsageAssignmentAudit.call

    assert_equal LlmUsageCatalog.keys, rows.pluck("usage_key")
    assert rows.all? { |row| row.fetch("status") == "healthy" }
  end

  test "reports missing and disabled assignments" do
    LlmUsageAssignment.find_by!(usage_key: "agent.intent").destroy!
    LlmUsageAssignment.find_by!(usage_key: "agent.planner").update!(enabled: false)

    rows = LlmUsageAssignmentAudit.call.index_by { |row| row.fetch("usage_key") }

    assert_equal "missing", rows.fetch("agent.intent").fetch("status")
    assert_equal "disabled", rows.fetch("agent.planner").fetch("status")
  end

  test "reports fallback as degraded when the primary connection is disabled" do
    primary = Model.find_by!(provider: "openai", model_id: service_connections(:gpt_oss).server_model)
    fallback = Model.find_by!(provider: "openai", model_id: service_connections(:llama_cpp).server_model)
    assignment = LlmUsageAssignment.find_by!(usage_key: "agent.draft")
    assignment.update!(model: primary, fallback_model: fallback)
    service_connections(:gpt_oss).update!(enabled: false)

    row = LlmUsageAssignmentAudit.call.find { |item| item.fetch("usage_key") == "agent.draft" }

    assert_equal "degraded", row.fetch("status")
    assert_includes row.fetch("issues"), "primary_unavailable"
    assert row.dig("fallback", "available")
  end
end
