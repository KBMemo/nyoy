# frozen_string_literal: true

require "test_helper"

class AgentGraphEvidenceSynthesizerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    AppSetting.instance.update!(research_draft_model_id: nil, research_draft_fallback: "main")
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
        "errors" => []
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
        "errors" => []
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
        "errors" => []
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

  test "draft system prompt delegates source list rendering to the system" do
    system = AgentGraph::EvidenceSynthesizer::SYNTHESIS_SYSTEM

    assert_includes system, "URL・出典リスト・「調査結果」見出しは付けない"
    assert_includes system, "追加の検索やページ取得が必要"
    assert_no_match(/文末に URL/, system)
    assert_no_match(/だけを根拠/, system)
  end

  test "disable_thinking! forces enable_thinking false on llm params" do
    synthesizer = AgentGraph::EvidenceSynthesizer.new(@chat)
    llm = Object.new
    llm.instance_variable_set(:@params, { top_p: 0.9, chat_template_kwargs: { "enable_thinking" => true } })
    llm.define_singleton_method(:with_params) do |**params|
      @params = params
      self
    end
    llm.define_singleton_method(:params) { @params }

    synthesizer.send(:disable_thinking!, llm)

    assert_equal false, llm.params.dig(:chat_template_kwargs, "enable_thinking")
    assert_equal 0.9, llm.params[:top_p]
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
