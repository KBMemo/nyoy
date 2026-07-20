# frozen_string_literal: true

require "test_helper"

class AgentGraphFinalAnswerSynthesizerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @state = {
      "question" => "高尾山の登山ルートは？",
      "draft" => "短いドラフト回答\n\n---\n\n### 出典\n- https://example.com",
      "memo_context" => nil,
      "search_results" => [],
      "fetched_pages" => [],
      "errors" => []
    }
  end

  test "passthrough returns approved draft" do
    previous = AgentGraph::FinalAnswerSynthesizer.force_passthrough
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = true

    answer, truncated, meta = AgentGraph::FinalAnswerSynthesizer.new(@chat).call(@state)

    assert_equal @state["draft"], answer
    assert_equal false, truncated
    assert_equal "draft", meta["source"]
  ensure
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = previous
  end

  test "llm failure returns nil so the run can surface a chat error" do
    synthesizer = AgentGraph::FinalAnswerSynthesizer.new(@chat)
    synthesizer.define_singleton_method(:ask_main_model) do |_evidence|
      [ nil, false, { "error" => "Faraday::ConnectionFailed: Connection refused", "model_id" => "gpt-oss" } ]
    end

    answer, _truncated, meta = synthesizer.call(@state)

    assert_nil answer
    assert_equal "error", meta["source"]
    assert_includes meta["error"], "Connection refused"
  end

  test "final prompt delegates source list rendering to the system" do
    system = AgentGraph::FinalAnswerSynthesizer::FINAL_SYSTEM
    prompt = AgentGraph::FinalAnswerSynthesizer.new(@chat).send(
      :user_prompt,
      {
        question: "出典は？",
        memo: nil,
        search_results: [],
        fetched_pages: [],
        evidence_review: {},
        errors: []
      }
    )

    assert_includes system, "URL・出典リスト・「調査結果」見出しは付けない"
    assert_includes prompt, "URL・出典リスト・「調査結果」見出しは付けない"
    assert_includes system, "追加の検索やページ取得が必要"
    assert_includes prompt, "追加検索やページ取得が必要"
    assert_no_match(/文末に関連 URL/, system)
    assert_no_match(/だけを根拠/, system)
  end

  test "final prompt asks for next research suggestions when evidence is limited" do
    prompt = AgentGraph::FinalAnswerSynthesizer.new(@chat).send(
      :user_prompt,
      {
        question: "最新の仕様は？",
        memo: nil,
        search_results: [],
        fetched_pages: [],
        plan: {
          "queries" => [ "仕様 2026", "公式 changelog", "移行ガイド" ],
          "searched_queries" => [ "仕様 2026" ],
          "fetch_urls" => [ "https://example.com/spec" ]
        },
        evidence_review: {
          "status" => "limited",
          "reason" => "available evidence is limited and no additional retrieval is available"
        },
        budget: { "fetched_urls" => [] },
        errors: []
      }
    )

    assert_includes AgentGraph::FinalAnswerSynthesizer::FINAL_SYSTEM, "次に試す検索語"
    assert_includes prompt, "証拠評価: status=limited"
    assert_includes prompt, "次に試す検索語"
    assert_includes prompt, "ユーザーに確認したい条件"
    assert_includes prompt, "追加調査候補:"
    assert_includes prompt, "検索: 公式 changelog"
    assert_includes prompt, "ページ取得: https://example.com/spec"
  end

  test "detects length finish reason on streamed final answer chunks" do
    synthesizer = AgentGraph::FinalAnswerSynthesizer.new(@chat)
    chunk = Object.new
    chunk.define_singleton_method(:finish_reason) { "length" }

    assert synthesizer.send(:length_finish_reason?, chunk)
  end

  test "live thinking includes unclosed think block while streaming" do
    synthesizer = AgentGraph::FinalAnswerSynthesizer.new(@chat)

    thinking = synthesizer.send(:live_thinking_text, "", "<think>ここまで考えた")

    assert_equal "ここまで考えた", thinking
  end

  test "final answer applies llama cache to main model" do
    model = @chat.model_association
    synthesizer = AgentGraph::FinalAnswerSynthesizer.new(@chat)
    llm = fake_llm(content: "最終回答")
    context = Object.new
    context.define_singleton_method(:chat) { |**| llm }

    cache_calls = []
    original_context_for = ChatModelCatalog.method(:context_for)
    original_cache_apply = ChatLlamaCache.method(:apply!)
    ChatModelCatalog.define_singleton_method(:context_for) { |_| context }
    ChatLlamaCache.define_singleton_method(:apply!) do |llm_chat, chat:, model: nil, slot_key: nil|
      cache_calls << { llm: llm_chat, chat: chat, model: model, slot_key: slot_key }
      llm_chat.instance_variable_set(:@nyoy_llama_cache_metadata, {
        enabled: true,
        cache_prompt: true,
        slot_id: 2,
        slot_count: 4
      })
      llm_chat
    end

    answer, _truncated, meta = synthesizer.send(:ask_main_model, {
      question: "質問",
      memo: nil,
      search_results: [],
      fetched_pages: [],
      evidence_review: {},
      errors: []
    })

    assert_equal "最終回答", answer
    assert_equal 1, cache_calls.size
    assert_same llm, cache_calls.first[:llm]
    assert_equal @chat, cache_calls.first[:chat]
    assert_equal model, cache_calls.first[:model]
    assert_equal "agent_graph:final:#{@chat.id}", cache_calls.first[:slot_key]
    assert_equal true, meta.dig("llama_cache", "cache_prompt")
    assert_equal 2, meta.dig("llama_cache", "slot_id")
    assert_equal 10, meta.dig("usage", "input_tokens")
    assert_equal 3, meta.dig("usage", "output_tokens")
  ensure
    ChatModelCatalog.define_singleton_method(:context_for, original_context_for)
    ChatLlamaCache.define_singleton_method(:apply!, original_cache_apply)
  end

  test "final answer accepts an explicit light model and cache slot" do
    model = @chat.model_association
    slot_key = "agent_graph:final_light:#{@chat.id}:#{model.model_id}"
    synthesizer = AgentGraph::FinalAnswerSynthesizer.new(
      @chat,
      model: model,
      source: "light",
      cache_slot_key: slot_key
    )
    llm = fake_llm(content: "軽量モデルの最終回答")
    context = Object.new
    context.define_singleton_method(:chat) { |**| llm }

    cache_calls = []
    original_context_for = ChatModelCatalog.method(:context_for)
    original_cache_apply = ChatLlamaCache.method(:apply!)
    ChatModelCatalog.define_singleton_method(:context_for) { |_| context }
    ChatLlamaCache.define_singleton_method(:apply!) do |llm_chat, chat:, model: nil, slot_key: nil|
      cache_calls << { llm: llm_chat, chat: chat, model: model, slot_key: slot_key }
      llm_chat
    end

    answer, _truncated, meta = synthesizer.send(:ask_main_model, evidence)

    assert_equal "軽量モデルの最終回答", answer
    assert_equal "light", meta.fetch("source")
    assert_equal model.model_id, meta.fetch("model_id")
    assert_equal slot_key, cache_calls.sole.fetch(:slot_key)
  ensure
    ChatModelCatalog.define_singleton_method(:context_for, original_context_for)
    ChatLlamaCache.define_singleton_method(:apply!, original_cache_apply)
  end

  private

  def evidence
    {
      question: "質問",
      memo: nil,
      search_results: [],
      fetched_pages: [],
      evidence_review: {},
      errors: []
    }
  end

  def fake_llm(content:)
    llm = Object.new
    llm.instance_variable_set(:@params, {})
    llm.define_singleton_method(:with_params) do |**params|
      @params = params
      self
    end
    llm.define_singleton_method(:with_temperature) { |_| self }
    llm.define_singleton_method(:with_instructions) { |_| self }
    llm.define_singleton_method(:ask) do |_prompt, &block|
      chunk = Struct.new(:content, :thinking, :finish_reason).new(content, nil, nil)
      chunk.define_singleton_method(:usage) do
        {
          "prompt_tokens" => 10,
          "completion_tokens" => 3
        }
      end
      block&.call(chunk)
      Struct.new(:content, :thinking, :raw).new(content, nil, nil)
    end
    llm
  end
end
