# frozen_string_literal: true

require "test_helper"

class AgentGraphRoleServicesTest < ActiveSupport::TestCase
  teardown do
    AgentGraph::RoleServices.reset!
  end

  test "fetches default final answer service" do
    service = AgentGraph::RoleServices.fetch(:final_answer)

    assert_instance_of AgentGraph::RoleServices::FinalAnswer, service
  end

  test "fetches default draft service" do
    service = AgentGraph::RoleServices.fetch(:draft)

    assert_instance_of AgentGraph::RoleServices::EvidencePackDraft, service
  end

  test "temporarily overrides a role service" do
    custom = Object.new

    AgentGraph::RoleServices.with(:final_answer, custom) do
      assert_same custom, AgentGraph::RoleServices.fetch(:final_answer)
    end

    assert_instance_of AgentGraph::RoleServices::FinalAnswer, AgentGraph::RoleServices.fetch(:final_answer)
  end

  test "unknown role raises an explicit error" do
    error = assert_raises(KeyError) { AgentGraph::RoleServices.fetch(:missing_role) }

    assert_includes error.message, "unknown AgentGraph role service"
  end
end
