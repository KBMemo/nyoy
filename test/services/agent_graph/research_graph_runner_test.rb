# frozen_string_literal: true

require "test_helper"

class AgentGraphResearchGraphRunnerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @chat.messages.create!(role: :user, content: "調査日：2024年の根拠はどこから来た？")
  end

  test "runs plan → recall → finalize and creates assistant message" do
    stub_recall(context: "メモ抜粋: 調査日は会話時点で誤って付けた") do
      stub_finalize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.completed?, -> { "status=#{run.status} error=#{run.error_message}" }
        assert_equal "research", run.graph_name
        assert run.agent_node_runs.where(status: "completed").exists?
        assert run.state["plan"]["need_memo"]
        assert_includes run.state["memo_context"], "調査日"
        assert run.state["final_answer"].present?

        message = @chat.messages.where(role: :assistant).order(:id).last
        assert message.present?
        assert_equal message.id, run.state["assistant_message_id"]
        assert_includes message.content, "調査結果"
      end
    end
  end

  test "records recall errors and still finalizes" do
    stub_recall(error: "rag down") do
      stub_finalize_without_llm do
        run = AgentGraph::ResearchGraphRunner.call(@chat)

        assert run.completed?
        assert_nil run.state["memo_context"]
        assert run.state["errors"].any? { |err| err["code"] == "RECALL_FAILED" }
        assert @chat.messages.where(role: :assistant).exists?
      end
    end
  end

  test "R1 runs search_web and fetch_urls when plan needs web" do
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
          stub_finalize_without_llm do
            run = AgentGraph::ResearchGraphRunner.call(@chat)

            assert run.completed?, -> { run.error_message }
            names = run.agent_node_runs.order(:id).pluck(:node_name)
            assert_includes names, "search_web"
            assert_includes names, "fetch_urls"
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
        stub_finalize_without_llm do
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

  def stub_finalize_without_llm
    original = AgentGraph::Nodes::FinalizeAnswer.instance_method(:llm_synthesize)
    AgentGraph::Nodes::FinalizeAnswer.define_method(:llm_synthesize) { |*| [ nil, false ] }
    yield
  ensure
    AgentGraph::Nodes::FinalizeAnswer.define_method(:llm_synthesize, original)
  end
end
