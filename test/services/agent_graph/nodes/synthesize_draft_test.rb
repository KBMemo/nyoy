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
  end
end
