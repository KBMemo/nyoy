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
        refute_includes run.agent_node_runs.pluck(:node_name), "await_approval"
        assert_includes run.agent_node_runs.pluck(:node_name), "finalize_answer"
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

  test "legacy reject under limit replans then finalizes" do
    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = create_pending_research_run!(
          question: "出典を調べて徒然に保存する前提で確認してから答えて",
          draft: "初稿ドラフト"
        )
        first_draft = run.state["draft"]

        resumed = AgentGraph::ResearchGraphRunner.resume(run, decision: "rejected")
        assert resumed.completed?, -> { "status=#{resumed.status} error=#{resumed.error_message}" }
        assert_equal 1, resumed.state["replan_count"]
        assert resumed.state["draft"].present?
        refute_equal first_draft, resumed.state["draft"]
        assert_includes resumed.state["draft"], "書き直し"
        assert resumed.state.dig("plan", "revision_hints").present?
        assert resumed.state.dig("plan", "replan")
        assert resumed.state["rejection_notes"].one?
        assert resumed.state["final_answer"].present?
        assert_includes resumed.agent_node_runs.pluck(:node_name), "finalize_answer"
        assert assistant_answer_messages.exists?
      end
    end
  end

  test "legacy reject at replan limit ends without publishing the draft" do
    stub_recall(context: "メモ") do
      stub_synthesize_without_llm do
        run = create_pending_research_run!(
          question: "出典を調べて徒然に保存する前提で確認してから答えて",
          draft: "初稿ドラフト",
          replan_count: AgentGraph::Nodes::AwaitApproval::MAX_REPLANS
        )

        completed = AgentGraph::ResearchGraphRunner.resume(run, decision: "rejected")
        assert completed.completed?, -> { "status=#{completed.status} error=#{completed.error_message}" }
        assert_equal AgentGraph::Nodes::AwaitApproval::MAX_REPLANS, completed.state["replan_count"]
        message = assistant_answer_messages.order(:id).last
        assert_includes message.content, "却下"
      end
    end
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
            assert_includes names, "synthesize_draft"
            assert_includes names, "finalize_answer"
            refute_includes names, "await_approval"
            assert run.state["search_results"].any?
            assert run.state["fetched_pages"].any?
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

  def create_pending_research_run!(question:, draft:, replan_count: 0)
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
        "replan_count" => replan_count,
        "plan" => {},
        "search_results" => [],
        "fetched_pages" => [],
        "errors" => [],
        "rejection_notes" => [],
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
