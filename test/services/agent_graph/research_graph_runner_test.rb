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
        assert_equal 3, run.agent_node_runs.where(status: "completed").count
        assert_equal 3, run.agent_checkpoints.count
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

  def stub_finalize_without_llm
    original = AgentGraph::Nodes::FinalizeAnswer.instance_method(:llm_synthesize)
    AgentGraph::Nodes::FinalizeAnswer.define_method(:llm_synthesize) { |*| [ nil, false ] }
    yield
  ensure
    AgentGraph::Nodes::FinalizeAnswer.define_method(:llm_synthesize, original)
  end
end
