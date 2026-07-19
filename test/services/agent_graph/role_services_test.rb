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

  test "fetches default evidence evaluator service" do
    service = AgentGraph::RoleServices.fetch(:evidence_evaluator)

    assert_instance_of AgentGraph::RoleServices::HeuristicEvidenceEvaluator, service
  end

  test "fetches default intent service" do
    service = AgentGraph::RoleServices.fetch(:intent)

    assert_instance_of AgentGraph::RoleServices::DeterministicIntentRouter, service
  end

  test "selects a built in role profile" do
    AgentGraph::RoleServices.select_profile(:draft, :llm)

    assert_equal :llm, AgentGraph::RoleServices.profile_for(:draft)
    assert_instance_of AgentGraph::RoleServices::LlmDraft, AgentGraph::RoleServices.fetch(:draft)
  end

  test "registers and selects a plugin role profile" do
    custom = Object.new
    AgentGraph::RoleServices.register_profile(:intent, :custom, -> { custom })
    AgentGraph::RoleServices.select_profile(:intent, :custom)

    assert_same custom, AgentGraph::RoleServices.fetch(:intent)
  end

  test "direct role override takes precedence over selected profile" do
    custom = Object.new
    AgentGraph::RoleServices.select_profile(:draft, :llm)
    AgentGraph::RoleServices.register(:draft, custom)

    assert_same custom, AgentGraph::RoleServices.fetch(:draft)
  end

  test "unknown profile raises an explicit error" do
    error = assert_raises(KeyError) do
      AgentGraph::RoleServices.select_profile(:draft, :missing)
    end

    assert_includes error.message, "unknown AgentGraph role service profile: draft.missing"
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
