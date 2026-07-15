# frozen_string_literal: true

require "test_helper"

class AgentGraphEvidenceSynthesizerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    AppSetting.instance.update!(research_draft_model_id: nil, research_draft_fallback: "main")
  end

  test "fallback draft changes after rejection notes" do
    synthesizer = AgentGraph::EvidenceSynthesizer.new(@chat)
    previous = AgentGraph::EvidenceSynthesizer.force_template
    AgentGraph::EvidenceSynthesizer.force_template = true

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
      assert_includes second, "（却下）"
    ensure
      AgentGraph::EvidenceSynthesizer.force_template = previous
    end
  end

  test "uses light model first then falls back to main" do
    light = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    main = Model.create!(
      provider: "openai",
      model_id: "research-main-test",
      name: "research-main-test",
      family: "local",
      context_window: 8192,
      capabilities: [ "chat" ],
      modalities: { "input" => [ "text" ], "output" => [ "text" ] },
      metadata: { "connection_key" => "gpt_oss", "api_base" => light.metadata["api_base"] }
    )
    original_chat_model = @chat.model_association
    @chat.update!(model: main)
    AppSetting.instance.update!(research_draft_model_id: light.model_id, research_draft_fallback: "main")

    calls = []
    original = AgentGraph::EvidenceSynthesizer.instance_method(:ask_model)
    AgentGraph::EvidenceSynthesizer.define_method(:ask_model) do |model, _evidence|
      calls << model.model_id
      if model.model_id == light.model_id
        [ nil, nil, false ]
      else
        [ "メインで書いたドラフト", "考えたこと", false ]
      end
    end

    begin
      draft, truncated, meta = AgentGraph::EvidenceSynthesizer.new(@chat).call(
        "question" => "出典は？",
        "memo_context" => nil,
        "search_results" => [],
        "fetched_pages" => [],
        "errors" => [],
        "rejection_notes" => [],
        "replan_count" => 0,
        "revision_hints" => []
      )

      assert_equal [ light.model_id, main.model_id ], calls
      assert_equal "メインで書いたドラフト", draft
      refute truncated
      assert_equal "main", meta["source"]
      assert_equal main.model_id, meta["model_id"]
      assert_equal "考えたこと", meta["thinking"]
    ensure
      AgentGraph::EvidenceSynthesizer.define_method(:ask_model, original)
      AgentGraph::EvidenceSynthesizer.send(:private, :ask_model)
      AppSetting.instance.update!(research_draft_model_id: nil, research_draft_fallback: "main")
      @chat.update!(model: original_chat_model)
      main.destroy!
    end
  end

  test "template fallback skips main when configured" do
    light = Model.find_by!(provider: "openai", model_id: "gpt-oss")
    AppSetting.instance.update!(research_draft_model_id: light.model_id, research_draft_fallback: "template")

    calls = []
    original = AgentGraph::EvidenceSynthesizer.instance_method(:ask_model)
    AgentGraph::EvidenceSynthesizer.define_method(:ask_model) do |model, _evidence|
      calls << model.model_id
      [ nil, nil, false ]
    end

    begin
      draft, _truncated, meta = AgentGraph::EvidenceSynthesizer.new(@chat).call(
        "question" => "出典は？",
        "memo_context" => "メモ",
        "search_results" => [],
        "fetched_pages" => [],
        "errors" => [],
        "rejection_notes" => [],
        "replan_count" => 0,
        "revision_hints" => []
      )

      assert_equal [ light.model_id ], calls
      assert_includes draft, "調査結果"
      assert_equal "template", meta["source"]
    ensure
      AgentGraph::EvidenceSynthesizer.define_method(:ask_model, original)
      AgentGraph::EvidenceSynthesizer.send(:private, :ask_model)
      AppSetting.instance.update!(research_draft_model_id: nil, research_draft_fallback: "main")
    end
  end

  test "llm draft appends evidence appendix so sources stay visible" do
    synthesizer = AgentGraph::EvidenceSynthesizer.new(@chat)
    original = AgentGraph::EvidenceSynthesizer.instance_method(:ask_model)
    AgentGraph::EvidenceSynthesizer.define_method(:ask_model) do |*|
      [ "短い回答本文", "調査の思考", false ]
    end

    begin
      draft, _truncated, meta = synthesizer.call(
        "question" => "出典は？",
        "memo_context" => "重要なメモ本文",
        "search_results" => [ {
          "results" => [ { "title" => "公式", "url" => "https://example.com/doc" } ]
        } ],
        "fetched_pages" => [],
        "errors" => [],
        "rejection_notes" => [],
        "replan_count" => 0,
        "revision_hints" => []
      )

      assert_includes draft, "短い回答本文"
      assert_includes draft, "### 出典"
      assert_includes draft, "重要なメモ本文"
      assert_includes draft, "https://example.com/doc"
      assert_equal "main", meta["source"]
      assert_equal "調査の思考", meta["thinking"]
    ensure
      AgentGraph::EvidenceSynthesizer.define_method(:ask_model, original)
      AgentGraph::EvidenceSynthesizer.send(:private, :ask_model)
    end
  end

  test "strips think blocks and keeps thinking for the UI" do
    synthesizer = AgentGraph::EvidenceSynthesizer.new(@chat)
    thinking = Struct.new(:text).new("フィールドの思考")
    response = Struct.new(:content, :thinking, :raw).new("<think>隠す</think>\n本文だけ", nil, nil)

    answer, extracted = synthesizer.send(:extract_answer_and_thinking, response)
    assert_equal "本文だけ", answer
    assert_equal "隠す", extracted

    empty = Struct.new(:content, :thinking, :raw).new("", thinking, nil)
    answer, extracted = synthesizer.send(:extract_answer_and_thinking, empty)
    assert_equal "フィールドの思考", answer
    assert_equal "フィールドの思考", extracted
  end
end
