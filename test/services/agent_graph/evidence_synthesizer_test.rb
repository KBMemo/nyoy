# frozen_string_literal: true

require "test_helper"

class AgentGraphEvidenceSynthesizerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "fallback draft changes after rejection notes" do
    synthesizer = AgentGraph::EvidenceSynthesizer.new(@chat)
    original = AgentGraph::EvidenceSynthesizer.instance_method(:llm_synthesize)
    AgentGraph::EvidenceSynthesizer.define_method(:llm_synthesize) { |*| [ nil, false ] }

    begin
      base_state = {
        "question" => "調査日の根拠は？",
        "memo_context" => "メモ抜粋",
        "search_results" => [],
        "fetched_pages" => [],
        "errors" => [],
        "replan_count" => 0,
        "rejection_notes" => []
      }

      first, = synthesizer.call(base_state)
      second, = synthesizer.call(
        base_state.merge(
          "replan_count" => 1,
          "rejection_notes" => [ {
            "replan_index" => 1,
            "draft_preview" => first.truncate(120)
          } ],
          "plan" => { "revision_hints" => [ "別の構成で" ] }
        )
      )

      refute_equal first, second
      assert_includes second, "書き直し"
      assert_includes second, "前回ドラフトで避けた点"
    ensure
      AgentGraph::EvidenceSynthesizer.define_method(:llm_synthesize, original)
    end
  end
end
