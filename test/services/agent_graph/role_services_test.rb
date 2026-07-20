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

  test "fetches default vision service" do
    service = AgentGraph::RoleServices.fetch(:vision)

    assert_instance_of AgentGraph::RoleServices::Vision, service
    assert_equal :main, AgentGraph::RoleServices.active_profile_for(:vision)
  end

  test "deterministic memo writer builds create and update drafts" do
    service = AgentGraph::RoleServices.fetch(:memo_writer)
    create_draft, create_display, create_metadata = service.call(
      action: :create,
      state: { "source_title" => "Title", "source_body" => "Body" },
      run: nil,
      chat: nil
    )
    update_draft, update_display, update_metadata = service.call(
      action: :update,
      state: {
        "memo_ref" => "42",
        "original_memo" => { "title" => "Existing", "updated_at" => "2026-07-16T00:00:00Z" },
        "plan" => { "mode" => "append" },
        "source_body" => "Added"
      },
      run: nil,
      chat: nil
    )

    assert_equal({ "action" => "create", "title" => "Title", "body" => "Body" }, create_draft)
    assert_equal "### Title\n\nBody", create_display
    assert_equal "deterministic", create_metadata.fetch("source")
    assert_equal "Added", update_draft.fetch("append_body")
    assert_equal "2026-07-16T00:00:00Z", update_draft.fetch("updated_at")
    assert_includes update_display, "本文末尾に追記"
    assert_equal "deterministic", update_metadata.fetch("source")
  end

  test "memo writer rejects an unknown action" do
    error = assert_raises(ArgumentError) do
      AgentGraph::RoleServices.fetch(:memo_writer).call(action: :delete, state: {}, run: nil, chat: nil)
    end

    assert_includes error.message, "unsupported memo writer action"
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

  test "deterministic planner does not treat a historical saved memo reference as sensitive" do
    plan, = AgentGraph::RoleServices.fetch(:planner).call(
      state: { "question" => "先週保存した登山計画メモの要点をまとめて" },
      run: nil,
      chat: nil
    )

    assert_equal false, plan["sensitive"]
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

  test "selects llm evidence evaluator profile" do
    AgentGraph::RoleServices.select_profile(:evidence_evaluator, :llm)

    assert_instance_of AgentGraph::LlmEvidenceEvaluator, AgentGraph::RoleServices.fetch(:evidence_evaluator)
  end

  test "selects hybrid llm intent profile" do
    AgentGraph::RoleServices.select_profile(:intent, :hybrid_llm)

    assert_instance_of AgentGraph::HybridLlmIntentRouter, AgentGraph::RoleServices.fetch(:intent)
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
