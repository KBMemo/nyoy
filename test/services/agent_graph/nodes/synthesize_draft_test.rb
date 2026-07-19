# frozen_string_literal: true

require "test_helper"

class AgentGraphNodesSynthesizeDraftTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "synthesize_draft",
      state: {}
    )
  end

  teardown do
    AgentGraph::RoleServices.reset!
  end

  test "records evidence counts in draft synthesis metadata" do
    result = AgentGraph::Nodes::SynthesizeDraft.new.call(
      state: {
        "question" => "根拠は？",
        "memo_context" => "関連メモ",
        "search_results" => [
          { "results" => [
            { "title" => "a", "url" => "https://example.com/a" },
            { "title" => "b", "url" => "https://example.com/b" }
          ] }
        ],
        "fetched_pages" => [
          { "title" => "page", "url" => "https://example.com/page" }
        ],
        "errors" => [ { "message" => "timeout" } ]
      },
      run: @run,
      chat: @chat
    )

    assert_equal false, result.failed?
    assert_equal({
      "memo" => 1,
      "search_results" => 2,
      "fetched_pages" => 1,
      "errors" => 1
    }, result.updates.dig("draft_synthesis", "evidence"))
    assert_equal "draft", result.updates.dig("draft_synthesis", "role")
    assert_equal "evidence_pack", result.updates.dig("draft_synthesis", "profile")
  end

  test "uses draft role service" do
    calls = []
    service = Object.new
    service.define_singleton_method(:call) do |state:, run:, chat:|
      calls << { state: state, run: run, chat: chat }
      [
        "draft from role",
        true,
        {
          "source" => "test",
          "model_id" => "tiny",
          "thinking" => "short thought"
        }
      ]
    end

    AgentGraph::RoleServices.with(:draft, service) do
      result = AgentGraph::Nodes::SynthesizeDraft.new.call(
        state: { "question" => "根拠は？" },
        run: @run,
        chat: @chat
      )

      assert_equal false, result.failed?
      assert_equal "draft from role", result.updates.fetch("draft")
      assert_equal true, result.updates.fetch("draft_truncated")
      assert_equal "short thought", result.updates.fetch("draft_thinking")
      assert_equal "test", result.updates.dig("draft_synthesis", "source")
      assert_equal "override", result.updates.dig("draft_synthesis", "profile")
      assert_equal "not_required", result.updates.fetch("approval")
    end

    assert_equal 1, calls.size
    assert_equal "根拠は？", calls.first.fetch(:state).fetch("question")
    assert_equal @run, calls.first.fetch(:run)
    assert_equal @chat, calls.first.fetch(:chat)
  end

  test "fails when draft role returns blank content" do
    service = Object.new
    service.define_singleton_method(:call) { |**| [ "", false, { "source" => "empty" } ] }

    AgentGraph::RoleServices.with(:draft, service) do
      result = AgentGraph::Nodes::SynthesizeDraft.new.call(
        state: { "question" => "根拠は？", "errors" => [] },
        run: @run,
        chat: @chat
      )

      assert result.failed?
      assert_equal "empty draft", result.error
      assert_equal "EMPTY_DRAFT", result.updates.dig("errors", 0, "code")
      assert_equal "override", result.updates.dig("draft_synthesis", "profile")
    end
  end
end
