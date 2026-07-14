# frozen_string_literal: true

require "test_helper"

class AgentGraphResearchGraphRunnerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @chat.messages.create!(role: :user, content: "調査日：2024年の根拠はどこから来た？")
  end

  test "non-sensitive research finalizes without approval interrupt" do
    stub_recall(context: "メモ抜粋: 調査日は会話時点で誤って付けた") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.completed?, -> { "status=#{run.status} error=#{run.error_message}" }
        refute run.state.dig("plan", "sensitive")
        assert_equal "not_required", run.state["approval"]
        assert run.state["final_answer"].present?

        names = run.agent_node_runs.order(:id).pluck(:node_name)
        assert_includes names, "synthesize_draft"
        refute_includes names, "await_approval"
        assert_includes names, "finalize_answer"

        message = @chat.messages.where(role: :assistant).order(:id).last
        assert message.present?
        assert_includes message.content, "調査結果"
      end
    end
  end

  test "sensitive plan awaits approval before finalizing" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "調査日の根拠を調べて確認してから答えて")

    stub_recall(context: "メモ抜粋: 調査日は会話時点で誤って付けた") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.awaiting_approval?, -> { "status=#{run.status} error=#{run.error_message}" }
        assert run.state.dig("plan", "sensitive")
        assert_equal "await_approval", run.current_node
        assert run.state["draft"].present?
        assert_equal "pending", run.state["approval"]
        refute @chat.messages.where(role: :assistant).exists?

        names = run.agent_node_runs.order(:id).pluck(:node_name)
        assert_includes names, "await_approval"
        refute_includes names, "finalize_answer"

        completed = AgentGraph::ResearchGraphRunner.resume(run, decision: "approved")
        assert completed.completed?, -> { completed.error_message }
        assert_equal "approved", completed.state["approval"]
        assert completed.state["final_answer"].present?
      end
    end
  end

  test "records recall errors and still finalizes when not sensitive" do
    stub_recall(error: "rag down") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.completed?
        assert_nil run.state["memo_context"]
        assert run.state["errors"].any? { |err| err["code"] == "RECALL_FAILED" }
        assert @chat.messages.where(role: :assistant).exists?
      end
    end
  end

  test "reject under limit replans instead of ending" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "出典を調べて徒然に保存する前提で確認してから答えて")

    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)
        assert run.awaiting_approval?
        first_draft = run.state["draft"]
        assert_equal 0, run.state["replan_count"].to_i

        resumed = AgentGraph::ResearchGraphRunner.resume(run, decision: "rejected")
        assert resumed.awaiting_approval?, -> { "status=#{resumed.status} error=#{resumed.error_message}" }
        assert_equal 1, resumed.state["replan_count"]
        assert resumed.state["draft"].present?
        refute_equal first_draft, resumed.state["draft"]
        assert_includes resumed.state["draft"], "書き直し"
        assert resumed.state.dig("plan", "revision_hints").present?
        assert resumed.state.dig("plan", "replan")
        assert resumed.state["rejection_notes"].one?
        names = resumed.agent_node_runs.order(:id).pluck(:node_name)
        assert names.count("plan_research") >= 2
        assert names.count("await_approval") >= 2
        refute @chat.messages.where(role: :assistant).exists?
      end
    end
  end

  test "reject at replan limit ends without publishing the draft" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "出典を調べて徒然に保存する前提で確認してから答えて")

    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)
        assert run.awaiting_approval?

        AgentGraph::Nodes::AwaitApproval::MAX_REPLANS.times do |index|
          run = AgentGraph::ResearchGraphRunner.resume(run, decision: "rejected")
          assert run.awaiting_approval?, -> { "replan #{index + 1}: status=#{run.status} error=#{run.error_message}" }
          assert_equal index + 1, run.state["replan_count"]
        end

        completed = AgentGraph::ResearchGraphRunner.resume(run, decision: "rejected")
        assert completed.completed?, -> { "status=#{completed.status} error=#{completed.error_message}" }
        assert_equal AgentGraph::Nodes::AwaitApproval::MAX_REPLANS, completed.state["replan_count"]
        message = @chat.messages.where(role: :assistant).order(:id).last
        assert_includes message.content, "却下"
      end
    end
  end

  test "R1 path searches and fetches then finalizes when not sensitive" do
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
            assert_includes names, "synthesize_draft"
            assert_includes names, "finalize_answer"
            refute_includes names, "await_approval"
            assert run.state["search_results"].any?
            assert run.state["fetched_pages"].any?
            assert_includes run.state["final_answer"], "example.com/rin"
            assert run.state.dig("budget", "searches_used").to_i.positive?
            assert run.state.dig("budget", "fetches_used").to_i.positive?
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
          refute_includes names, "search_web"
          assert_equal [ "https://docs.example.com/page" ], run.state.dig("plan", "fetch_urls")
          assert run.state["fetched_pages"].any? { |page| page["url"] == "https://docs.example.com/page" }
        end
      end
    end
  end

  test "auto_approve skips interrupt even when plan is sensitive" do
    @chat.messages.destroy_all
    @chat.messages.create!(role: :user, content: "調査して確認してから答えて")

    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat, auto_approve: true)

        assert run.completed?, -> { run.error_message }
        assert run.state.dig("plan", "sensitive")
        assert_equal "not_required", run.state["approval"]
        assert run.state["final_answer"].present?
        refute_includes run.agent_node_runs.pluck(:node_name), "await_approval"
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

  test "starting a new run cancels earlier pending approval on the same chat" do
    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        first = AgentGraph::ResearchGraphRunner.call(
          @chat,
          question: "調査して確認してから答えて"
        )
        assert first.awaiting_approval?

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
