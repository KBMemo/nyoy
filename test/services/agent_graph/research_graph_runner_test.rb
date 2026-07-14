# frozen_string_literal: true

require "test_helper"

class AgentGraphResearchGraphRunnerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @chat.messages.create!(role: :user, content: "調査日：2024年の根拠はどこから来た？")
  end

  test "R2 runs synthesize then awaits approval before finalizing" do
    stub_recall(context: "メモ抜粋: 調査日は会話時点で誤って付けた") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.awaiting_approval?, -> { "status=#{run.status} error=#{run.error_message}" }
        assert_equal "await_approval", run.current_node
        assert run.state["draft"].present?
        assert_equal "pending", run.state["approval"]
        assert_includes run.state["draft"], "調査結果"
        assert_nil run.state["final_answer"]
        refute @chat.messages.where(role: :assistant).exists?

        names = run.agent_node_runs.order(:id).pluck(:node_name)
        assert_includes names, "synthesize_draft"
        assert_includes names, "await_approval"
        refute_includes names, "finalize_answer"

        completed = AgentGraph::ResearchGraphRunner.resume(run, decision: "approved")
        assert completed.completed?, -> { completed.error_message }
        assert_equal "approved", completed.state["approval"]
        assert completed.state["final_answer"].present?

        message = @chat.messages.where(role: :assistant).order(:id).last
        assert message.present?
        assert_equal message.id, completed.state["assistant_message_id"]
        assert_includes message.content, "調査結果"
      end
    end
  end

  test "records recall errors and still drafts then awaits approval" do
    stub_recall(error: "rag down") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.awaiting_approval?
        assert_nil run.state["memo_context"]
        assert run.state["errors"].any? { |err| err["code"] == "RECALL_FAILED" }
        assert run.state["draft"].present?

        AgentGraph::ResearchGraphRunner.resume(run, decision: "approved")
        assert @chat.messages.where(role: :assistant).exists?
      end
    end
  end

  test "reject ends without publishing the draft" do
    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)
        assert run.awaiting_approval?

        completed = AgentGraph::ResearchGraphRunner.resume(run, decision: "rejected")
        assert completed.completed?
        message = @chat.messages.where(role: :assistant).order(:id).last
        assert_includes message.content, "却下"
        refute_equal run.state["draft"], message.content
      end
    end
  end

  test "R1 path still searches and fetches before draft approval" do
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

            assert run.awaiting_approval?, -> { run.error_message }
            names = run.agent_node_runs.order(:id).pluck(:node_name)
            assert_includes names, "search_web"
            assert_includes names, "fetch_urls"
            assert_includes names, "synthesize_draft"
            assert run.state["search_results"].any?
            assert run.state["fetched_pages"].any?
            assert_includes run.state["draft"], "example.com/rin"
            assert run.state.dig("budget", "searches_used").to_i.positive?
            assert run.state.dig("budget", "fetches_used").to_i.positive?

            completed = AgentGraph::ResearchGraphRunner.resume(run, decision: "approved")
            assert completed.completed?
            assert_includes completed.state["final_answer"], "example.com/rin"
          end
        end
      end
    end
  end

  test "R1 fetches URLs embedded in the question without searching" do
    @chat.messages.destroy_all
    @chat.messages.create!(
      role: :user,
      content: "このページを確認して https://docs.example.com/page"
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

          assert run.awaiting_approval?, -> { run.error_message }
          names = run.agent_node_runs.order(:id).pluck(:node_name)
          assert_includes names, "fetch_urls"
          refute_includes names, "search_web"
          assert_equal [ "https://docs.example.com/page" ], run.state.dig("plan", "fetch_urls")
          assert run.state["fetched_pages"].any? { |page| page["url"] == "https://docs.example.com/page" }
        end
      end
    end
  end

  test "auto_approve skips interrupt and finalizes" do
    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat, auto_approve: true)

        assert run.completed?, -> { run.error_message }
        assert_equal "approved", run.state["approval"]
        assert run.state["final_answer"].present?
        assert @chat.messages.where(role: :assistant).exists?
      end
    end
  end

  test "call_for_mcp creates a chat when chat_id omitted" do
    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call_for_mcp(
          question: "調査の根拠は？",
          auto_approve: true
        )

        assert run.completed?
        assert run.chat.present?
        assert_equal "調査の根拠は？", run.state["question"]
      end
    end
  end

  private

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
    original = AgentGraph::EvidenceSynthesizer.instance_method(:llm_synthesize)
    AgentGraph::EvidenceSynthesizer.define_method(:llm_synthesize) { |*| [ nil, false ] }
    yield
  ensure
    AgentGraph::EvidenceSynthesizer.define_method(:llm_synthesize, original)
  end
end
