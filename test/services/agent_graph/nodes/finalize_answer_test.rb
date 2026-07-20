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
    service = Object.new
    service.define_singleton_method(:call) do |state:, run:, chat:|
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

    AgentGraph::RoleServices.with(:final_answer, service) do
      result = AgentGraph::Nodes::FinalizeAnswer.new.call(
        state: @run.state,
        run: @run,
        chat: @chat
      )

      assert result.failed?
      assert_includes result.error, "モデルサーバーに接続できません"
      assert_includes result.error, "起動しているか確認"
      assert_equal 0, @chat.messages.where(role: :assistant).count
      assert_equal "final_answer", result.updates.dig("final_synthesis", "role")
      assert_equal "override", result.updates.dig("final_synthesis", "profile")
    end
  end

  test "uses final answer role service" do
    calls = []
    service = Object.new
    service.define_singleton_method(:call) do |state:, run:, chat:|
      calls << { state: state, run: run, chat: chat }

      [
        "role service answer",
        false,
        [
          [ "source", "test" ],
          [ "thinking", "reasoning" ]
        ].to_h
      ]
    end

    AgentGraph::RoleServices.with(:final_answer, service) do
      result = AgentGraph::Nodes::FinalizeAnswer.new.call(
        state: @run.state,
        run: @run,
        chat: @chat
      )

      assert result.finished?
      assert_equal "role service answer", result.updates.fetch("final_answer")
      message = @chat.messages.where(role: :assistant).sole
      assert_equal "role service answer", message.content
      assert_equal "reasoning", message.thinking_text
      assert_equal "test", result.updates.dig("final_synthesis", "source")
      assert_equal "final_answer", result.updates.dig("final_synthesis", "role")
      assert_equal "override", result.updates.dig("final_synthesis", "profile")
    end

    assert_equal 1, calls.size
    assert_equal "調べて", calls.first.fetch(:state).fetch("question")
    assert_equal @run, calls.first.fetch(:run)
    assert_equal @chat, calls.first.fetch(:chat)
  end

  test "records the built in final answer profile" do
    previous = AgentGraph::FinalAnswerSynthesizer.force_passthrough
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = true

    result = AgentGraph::Nodes::FinalizeAnswer.new.call(state: @run.state, run: @run, chat: @chat)

    assert result.finished?
    assert_equal "final_answer", result.updates.dig("final_synthesis", "role")
    assert_equal "main", result.updates.dig("final_synthesis", "profile")
  ensure
    AgentGraph::FinalAnswerSynthesizer.force_passthrough = previous
  end
end
