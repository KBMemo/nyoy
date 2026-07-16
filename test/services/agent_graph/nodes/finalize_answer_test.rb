# frozen_string_literal: true

require "test_helper"

class AgentGraphNodesFinalizeAnswerTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @run = AgentRun.create!(
      chat: @chat,
      graph_name: AgentGraph::ResearchGraph::NAME,
      status: "running",
      current_node: "finalize_answer",
      started_at: Time.current,
      state: {
        "question" => "調べて",
        "draft" => "### 調査結果\n出典あり",
        "approval" => "not_required"
      }
    )
  end

  test "fails the node when the model server is unreachable" do
    original_new = AgentGraph::FinalAnswerSynthesizer.method(:new)
    AgentGraph::FinalAnswerSynthesizer.define_singleton_method(:new) do |_chat|
      synthesizer = Object.new
      synthesizer.define_singleton_method(:call) do |_state|
        [
          nil,
          false,
          {
            "source" => "error",
            "error" => "Faraday::ConnectionFailed: Connection refused",
            "model_id" => "gpt-oss"
          }
        ]
      end
      synthesizer
    end

    result = AgentGraph::Nodes::FinalizeAnswer.new.call(
      state: @run.state,
      run: @run,
      chat: @chat
    )

    assert result.failed?
    assert_includes result.error, "モデルサーバーに接続できません"
    assert_includes result.error, "起動しているか確認"
    assert_equal 0, @chat.messages.where(role: :assistant).count
  ensure
    AgentGraph::FinalAnswerSynthesizer.define_singleton_method(:new, original_new)
  end
end
