# frozen_string_literal: true

require "test_helper"

class LlmUsageResolverTest < ActiveSupport::TestCase
  setup do
    LlmUsageAssignment.delete_all
    ChatModelCatalog.seed!
  end

  test "resolves an enabled assignment to its model and connection" do
    model = model_for("gpt_oss")
    assignment = LlmUsageAssignment.create!(usage_key: "agent.draft", model: model)

    resolution = LlmUsageResolver.resolve("agent.draft")

    assert_equal assignment, resolution.assignment
    assert_equal model, resolution.model
    assert_equal service_connections(:gpt_oss), resolution.connection
    assert_equal service_connections(:gpt_oss), model.service_connection
  end

  test "uses fallback model when the primary connection is disabled" do
    primary = model_for("gpt_oss")
    fallback = model_for("llama_cpp")
    service_connections(:gpt_oss).update!(enabled: false)
    LlmUsageAssignment.create!(usage_key: "agent.draft", model: primary, fallback_model: fallback)

    resolution = LlmUsageResolver.resolve("agent.draft")

    assert_equal fallback, resolution.model
    assert_equal service_connections(:llama_cpp), resolution.connection
  end

  test "raises when a client assignment is missing" do
    error = assert_raises(LlmUsageResolver::MissingAssignmentError) do
      LlmUsageResolver.llama_client_for("agent.draft")
    end

    assert_includes error.message, "agent.draft"
  end

  test "returns nil for a disabled assignment" do
    LlmUsageAssignment.create!(usage_key: "agent.draft", model: model_for("llama_cpp"), enabled: false)

    assert_nil LlmUsageResolver.resolve("agent.draft")
  end

  test "does not resolve an unassociated model" do
    model = model_for("llama_cpp")
    model.update_columns(service_connection_id: nil)
    LlmUsageAssignment.create!(usage_key: "agent.draft", model: model)

    assert_nil LlmUsageResolver.resolve("agent.draft")
  end

  private

  def model_for(connection_key)
    connection = service_connections(connection_key)
    Model.find_by!(provider: "openai", model_id: connection.server_model)
  end
end
