# frozen_string_literal: true

require "test_helper"

class AgentGraphResearchGraphRunnerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @chat.messages.create!(role: :user, content: "調査日：2024年の根拠はどこから来た？")
  end

  test "research finalizes immediately without draft approval" do
    stub_recall(context: "メモ抜粋: 調査日は会話時点で誤って付けた") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.completed?, -> { "status=#{run.status} error=#{run.error_message}" }
        assert_equal "not_required", run.state["approval"]
        assert run.state["draft"].present?
        assert run.state["final_answer"].present?
        names = run.agent_node_runs.order(:id).pluck(:node_name)
        refute_includes names, "await_approval"
        assert_includes names, "evaluate_evidence"
        assert_includes names, "finalize_answer"
        assert_operator names.index("evaluate_evidence"), :<, names.index("finalize_answer")
        assert_equal "sufficient", run.state.dig("evidence_review", "status")
        assert assistant_answer_messages.exists?
      end
    end
  end

  test "auto_approve flag is accepted but unnecessary for completion" do
    stub_recall(context: "メモ抜粋: 調査日は会話時点で誤って付けた") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat, auto_approve: true)

        assert run.completed?, -> { "status=#{run.status} error=#{run.error_message}" }
        assert_equal "not_required", run.state["approval"]
        refute_includes run.agent_node_runs.pluck(:node_name), "await_approval"
        assert_includes run.agent_node_runs.pluck(:node_name), "finalize_answer"
        assert assistant_answer_messages.exists?
      end
    end
  end

  test "records router intent metadata in initial state" do
    stub_recall(context: "メモ抜粋") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(
          @chat,
          routing: { reason: "llm_research_escalation", model_id: "tiny" }
        )

        assert_equal "llm_research_escalation", run.state.dig("routing", "reason")
        assert_equal "tiny", run.state.dig("routing", "model_id")
      end
    end
  end

  test "sensitive plan also finalizes without approval" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "調査日の根拠を調べて確認してから答えて")

    stub_recall(context: "メモ抜粋: 調査日は会話時点で誤って付けた") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.completed?, -> { "status=#{run.status} error=#{run.error_message}" }
        assert run.state.dig("plan", "sensitive")
        assert_equal "not_required", run.state["approval"]
        refute_includes run.agent_node_runs.pluck(:node_name), "await_approval"
        assert_includes run.agent_node_runs.pluck(:node_name), "finalize_answer"
        assert run.state["final_answer"].present?
        assert assistant_answer_messages.exists?
      end
    end
  end

  test "records recall errors and still finalizes" do
    stub_recall(error: "rag down") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.completed?, -> { "status=#{run.status} error=#{run.error_message}" }
        assert_nil run.state["memo_context"]
        assert run.state["errors"].any? { |err| err["code"] == "RECALL_FAILED" }
        assert assistant_answer_messages.exists?
        assert @chat.messages.joins(:tool_calls).exists?
      end
    end
  end

  test "research approval resume is no longer supported" do
    run = create_pending_research_run!(
      question: "出典を調べて徒然に保存する前提で確認してから答えて",
      draft: "初稿ドラフト"
    )

    error = assert_raises(ArgumentError) do
      AgentGraph::ResearchGraphRunner.resume(run, decision: "rejected")
    end
    assert_includes error.message, "no longer supported"
  end

  test "R1 path searches and fetches then finalizes" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "最新の Hydrangea Rin 公式情報を調べて")

    stub_recall(context: nil) do
      stub_web_search(results: [ {
        "title" => "Rin cultivar",
        "url" => "https://example.com/rin",
        "content" => "八重咲き"
      } ]) do
        stub_fetch_url(
          url: "https://example.com/rin",
          payload: {
            "ok" => true,
            "url" => "https://example.com/rin",
            "title" => "Rin",
            "content_preview" => "装飾花は八重咲き"
          }
        ) do
          stub_synthesize_without_llm do
            run = AgentGraph::ResearchGraphRunner.call(@chat)

            assert run.completed?, -> { run.error_message }
            names = run.agent_node_runs.order(:id).pluck(:node_name)
            assert_includes names, "search_web"
            assert_includes names, "fetch_urls"
            assert_includes names, "evaluate_evidence"
            assert_includes names, "synthesize_draft"
            assert_includes names, "finalize_answer"
            assert_operator names.index("fetch_urls"), :<, names.index("evaluate_evidence")
            assert_operator names.index("evaluate_evidence"), :<, names.index("synthesize_draft")
            refute_includes names, "await_approval"
            assert run.state["search_results"].any?
            assert run.state["fetched_pages"].any?
            assert_equal "sufficient", run.state.dig("evidence_review", "status")
            assert_equal "synthesize_draft", run.state.dig("evidence_review", "next_node")
            assert_includes run.state["draft"], "example.com/rin"
            assert_includes run.state["final_answer"], "example.com/rin"
            assert run.state.dig("budget", "searches_used").to_i.positive?
            assert run.state.dig("budget", "fetches_used").to_i.positive?

            tool_names = @chat.messages.flat_map { |m| m.tool_calls_association.pluck(:name) }
            assert_includes tool_names, "web_search"
            assert_includes tool_names, "fetch_url"
            assert_includes tool_names, "recall_memos"
            assert @chat.messages.where(role: :tool).exists?
          end
        end
      end
    end
  end

  test "R1 retries a remaining search query when first search has no fetchable results" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "高尾山から景信山への登山道を調べて")

    stub_search_queries([ "first query", "second query", "third query" ]) do
      stub_searfront_settings(max_searches_per_turn: 3) do
        stub_recall(context: nil) do
          stub_web_search_by_query(
            "first query" => [],
            "second query" => [],
            "third query" => [ {
              "title" => "高尾山から景信山",
              "url" => "https://example.com/trail",
              "content" => "登山ルート"
            } ]
          ) do |queries|
            stub_fetch_url(
              url: "https://example.com/trail",
              payload: {
                "ok" => true,
                "url" => "https://example.com/trail",
                "title" => "Trail",
                "content_preview" => "高尾山から景信山への登山道"
              }
            ) do
              stub_synthesize_without_llm do
                run = AgentGraph::ResearchGraphRunner.call(@chat)

                assert run.completed?, -> { run.error_message }
                assert_equal [ "first query", "second query", "third query" ], queries
                assert_equal queries, run.state.dig("plan", "searched_queries")
                assert_equal "sufficient", run.state.dig("evidence_review", "status")
                assert run.state["fetched_pages"].any? { |page| page["url"] == "https://example.com/trail" }
                assert_operator run.agent_node_runs.where(node_name: "search_web").count, :>=, 2
              end
            end
          end
        end
      end
    end
  end

  test "R1 fetches URLs embedded in the question without searching" do
    @chat.messages.destroy_all
    @chat.messages.create!(
      role: :user,
      content: "このページを見て https://docs.example.com/page"
    )

    stub_recall(context: nil) do
      stub_fetch_url(
        url: "https://docs.example.com/page",
        payload: {
          "ok" => true,
          "url" => "https://docs.example.com/page",
          "title" => "Spec page",
          "content_preview" => "根拠ドキュメント"
        }
      ) do
        stub_synthesize_without_llm do
          run = AgentGraph::ResearchGraphRunner.call(@chat)

          assert run.completed?, -> { run.error_message }
          names = run.agent_node_runs.order(:id).pluck(:node_name)
          assert_includes names, "fetch_urls"
          assert_includes names, "finalize_answer"
          refute_includes names, "search_web"
          assert_equal [ "https://docs.example.com/page" ], run.state.dig("plan", "fetch_urls")
          assert run.state["fetched_pages"].any? { |page| page["url"] == "https://docs.example.com/page" }
        end
      end
    end
  end

  test "call_for_mcp creates a chat when chat_id omitted" do
    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call_for_mcp(
          question: "調査の根拠は？",
          auto_approve: false
        )

        assert run.completed?
        assert run.chat.present?
        assert_equal "調査の根拠は？", run.state["question"]
      end
    end
  end

  test "starting a new run cancels earlier pending approval on the same chat" do
    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        first = create_pending_research_run!(question: "調査して確認してから答えて", draft: "旧ドラフト")

        second = AgentGraph::ResearchGraphRunner.call(
          @chat,
          question: "出典の根拠は？"
        )

        assert_equal "cancelled", first.reload.status
        assert_includes first.error_message, "superseded"
        assert second.completed?
        assert_equal 0, @chat.agent_runs.pending_decision.count
      end
    end
  end

  private

  def create_pending_research_run!(question:, draft:)
    AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "awaiting_approval",
      current_node: "await_approval",
      started_at: Time.current,
      state: {
        "question" => question,
        "draft" => draft,
        "approval" => "pending",
        "auto_approve" => false,
        "plan" => {},
        "search_results" => [],
        "fetched_pages" => [],
        "errors" => [],
        "budget" => { "searches_used" => 0, "fetches_used" => 0 }
      }
    )
  end

  def assistant_answer_messages
    @chat.messages.where(role: :assistant).where.missing(:tool_calls)
  end

  def stub_recall(context: nil, error: nil)
    original = ChatTools::RecallMemos.instance_method(:execute)
    ChatTools::RecallMemos.define_method(:execute) do |query:|
      error ? { error: error } : { context: context }
    end
    yield
  ensure
    ChatTools::RecallMemos.define_method(:execute, original)
  end

  def stub_web_search(results:)
    original = ChatTools::WebSearch.instance_method(:execute)
    ChatTools::WebSearch.define_method(:execute) do |q:, limit: nil|
      if (error = @budget.consume_search!)
        error
      else
        { "query" => q, "results" => results, "number_of_results" => results.size }
      end
    end
    yield
  ensure
    ChatTools::WebSearch.define_method(:execute, original)
  end

  def stub_web_search_by_query(results_by_query)
    queries = []
    original = ChatTools::WebSearch.instance_method(:execute)
    ChatTools::WebSearch.define_method(:execute) do |q:, limit: nil|
      queries << q
      if (error = @budget.consume_search!)
        error
      else
        results = Array(results_by_query.fetch(q, []))
        { "query" => q, "results" => results, "number_of_results" => results.size }
      end
    end
    yield queries
  ensure
    ChatTools::WebSearch.define_method(:execute, original)
  end

  def stub_search_queries(queries)
    original = AgentGraph::SearchQueryNormalizer.method(:queries_for)
    AgentGraph::SearchQueryNormalizer.define_singleton_method(:queries_for) { |_question| queries }
    yield
  ensure
    AgentGraph::SearchQueryNormalizer.define_singleton_method(:queries_for) { |question| original.call(question) }
  end

  def stub_searfront_settings(overrides)
    original = SearfrontSettings.method(:load)
    settings = SearfrontSettings.from(SearfrontSettings::DEFAULTS.merge(overrides.stringify_keys))
    SearfrontSettings.define_singleton_method(:load) { settings }
    yield
  ensure
    SearfrontSettings.define_singleton_method(:load) { original.call }
  end

  def stub_fetch_url(url:, payload:)
    original = ChatTools::FetchUrl.instance_method(:execute)
    ChatTools::FetchUrl.define_method(:execute) do |url:|
      if (error = @budget.consume_fetch!(url: url))
        error
      else
        ChatTools::ToolResponse.preview(payload.merge("tool" => "fetch_url"))
      end
    end
    yield
  ensure
    ChatTools::FetchUrl.define_method(:execute, original)
  end

  def stub_synthesize_without_llm
    previous_draft = AgentGraph::EvidenceSynthesizer.force_template
    previous_final = AgentGraph::FinalAnswerSynthesizer.force_passthrough
    AgentGraph::EvidenceSynthesizer.force_template = true
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = true
    yield
  ensure
    AgentGraph::EvidenceSynthesizer.force_template = previous_draft
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = previous_final
  end
end
