# frozen_string_literal: true

require "test_helper"

class AgentNodeRunTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "finalize_answer",
      state: {}
    )
  end

  test "output_summary reports common node result fields" do
    node_run = @run.agent_node_runs.create!(
      node_name: "finalize_answer",
      status: "failed",
      output_snapshot: {
        "updates" => { "final_answer" => "answer", "truncated" => false },
        "goto" => "done",
        "interrupt" => true,
        "error" => "boom"
      }
    )

    assert_equal [
      "updates: final_answer, truncated",
      "goto: done",
      "interrupt",
      "error: boom"
    ], node_run.output_summary
  end

  test "output_summary reports empty output" do
    node_run = @run.agent_node_runs.create!(
      node_name: "plan_research",
      status: "completed",
      output_snapshot: {}
    )

    assert_equal [ "no output" ], node_run.output_summary
  end

  test "output_summary reports synthesis metadata" do
    node_run = @run.agent_node_runs.create!(
      node_name: "finalize_answer",
      status: "completed",
      output_snapshot: {
        "updates" => {
          "final_answer" => "answer",
          "truncated" => true,
          "final_synthesis" => {
            "source" => "main",
            "model_id" => "gpt-oss",
            "llama_cache" => {
              "cache_prompt" => true,
              "slot_id" => 2,
              "slot_count" => 4
            },
            "usage" => {
              "input_tokens" => 100,
              "output_tokens" => 20,
              "cached_tokens" => 80
            }
          }
        }
      }
    )

    assert_equal [
      "updates: final_answer, truncated, final_synthesis",
      "llm: gpt-oss",
      "source: main",
      "cache_prompt",
      "slot: 2/4",
      "in: 100",
      "out: 20",
      "cached: 80",
      "truncated"
    ], node_run.output_summary
  end

  test "output_summary reports draft evidence metadata" do
    node_run = @run.agent_node_runs.create!(
      node_name: "synthesize_draft",
      status: "completed",
      output_snapshot: {
        "updates" => {
          "draft" => "draft",
          "draft_synthesis" => {
            "role" => "draft",
            "profile" => "llm",
            "source" => "evidence_pack",
            "fallback" => "template",
            "evidence" => {
              "memo" => 1,
              "search_results" => 2,
              "fetched_pages" => 1,
              "errors" => 0
            }
          }
        }
      }
    )

    assert_equal [
      "updates: draft, draft_synthesis",
      "profile: draft.llm",
      "source: evidence_pack",
      "fallback: template",
      "memo: 1",
      "search: 2",
      "fetched: 1",
      "errors: 0"
    ], node_run.output_summary
  end

  test "output_summary reports planner metadata" do
    node_run = @run.agent_node_runs.create!(
      node_name: "plan_research",
      status: "completed",
      output_snapshot: {
        "updates" => {
          "plan" => { "need_web" => true },
          "planning" => {
            "role" => "planner",
            "profile" => "llm",
            "source" => "deterministic",
            "model_id" => "qwen3.5-4b",
            "fallback" => "deterministic",
            "llama_cache" => {
              "cache_prompt" => true,
              "slot_id" => 1,
              "slot_count" => 4
            },
            "usage" => {
              "input_tokens" => 80,
              "output_tokens" => 12,
              "cached_tokens" => 60
            }
          }
        }
      }
    )

    assert_equal [
      "updates: plan, planning",
      "profile: planner.llm",
      "llm: qwen3.5-4b",
      "source: deterministic",
      "fallback: deterministic",
      "cache_prompt",
      "slot: 1/4",
      "in: 80",
      "out: 12",
      "cached: 60"
    ], node_run.output_summary
  end

  test "output_summary reports evidence evaluator metadata" do
    node_run = @run.agent_node_runs.create!(
      node_name: "evaluate_evidence",
      status: "completed",
      output_snapshot: {
        "updates" => {
          "evidence_review" => {
            "status" => "sufficient",
            "role" => "evidence_evaluator",
            "profile" => "llm",
            "source" => "light",
            "model_id" => "tiny",
            "fallback" => "heuristic",
            "llama_cache" => { "cache_prompt" => true, "slot_id" => 0, "slot_count" => 2 },
            "usage" => { "input_tokens" => 40, "output_tokens" => 8, "cached_tokens" => 25 }
          }
        }
      }
    )

    assert_equal [
      "updates: evidence_review",
      "profile: evidence_evaluator.llm",
      "llm: tiny",
      "source: light",
      "fallback: heuristic",
      "cache_prompt",
      "slot: 0/2",
      "in: 40",
      "out: 8",
      "cached: 25"
    ], node_run.output_summary
  end
end
