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

  test "fetches default planner service" do
    service = AgentGraph::RoleServices.fetch(:planner)

    assert_instance_of AgentGraph::RoleServices::DeterministicResearchPlanner, service
  end

  test "deterministic planner preserves the research plan contract" do
    plan, metadata = AgentGraph::RoleServices.fetch(:planner).call(
      state: { "question" => "https://example.com を調べて、公開前に確認してから保存" },
      run: nil,
      chat: nil
    )

    assert_equal true, plan["need_memo"]
    assert_equal true, plan["need_web"]
    assert_equal true, plan["sensitive"]
    assert_equal [ "https://example.com" ], plan["fetch_urls"]
    assert plan["queries"].any?
    assert_equal "deterministic", metadata["source"]
  end

  test "selects a built in role profile" do
    AgentGraph::RoleServices.select_profile(:draft, :llm)

    assert_equal :llm, AgentGraph::RoleServices.profile_for(:draft)
    assert_instance_of AgentGraph::RoleServices::LlmDraft, AgentGraph::RoleServices.fetch(:draft)
  end

  test "selects llm planner profile" do
    AgentGraph::RoleServices.select_profile(:planner, :llm)

    assert_instance_of AgentGraph::LlmResearchPlanner, AgentGraph::RoleServices.fetch(:planner)
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
