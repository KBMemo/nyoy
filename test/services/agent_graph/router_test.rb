# frozen_string_literal: true

require "test_helper"

class AgentGraphRouterTest < ActiveSupport::TestCase
  setup do
    model = Model.find_or_create_by!(provider: "test", model_id: "router-test") do |record|
      record.name = "Router Test"
    end
    @chat = Chat.create!(model: model)
  end

  test "routes clear memo write turn to memo write graph" do
    add_user_message("この回答をメモに保存して")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::MemoWriteGraph::NAME, decision.graph_name
    assert_equal AgentGraph::MemoWriteGraphRunner, decision.runner
    assert decision.memo_write?
    refute decision.research?
    assert_equal "strong", decision.intent_decision[:reason]
  end

  test "routes research turn to research graph" do
    add_user_message("最新情報を調べて")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::ResearchGraph::NAME, decision.graph_name
    assert_equal AgentGraph::ResearchGraphRunner, decision.runner
    assert decision.research?
    refute decision.memo_write?
    assert_equal "strong", decision.intent_decision[:reason]
  end

  test "memo write is evaluated before research" do
    add_user_message("この回答を徒然に保存して。出典も残して")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::MemoWriteGraph::NAME, decision.graph_name
  end

  test "memo update is evaluated before memo write" do
    add_user_message("メモ 42 に追記して\n追加本文")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::MemoUpdateGraph::NAME, decision.graph_name
    assert_equal AgentGraph::MemoUpdateGraphRunner, decision.runner
  end

  test "research-framed memo save defers to research graph" do
    add_user_message("根拠を調査してメモに保存して")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::ResearchGraph::NAME, decision.graph_name
  end

  test "returns nil for ordinary chat" do
    add_user_message("こんにちは")

    assert_nil AgentGraph::Router.route(@chat)
  end

  test "uses latest user message" do
    add_user_message("最新情報を調べて")
    add_assistant_message("調査結果です")
    add_user_message("ありがとう")

    assert_nil AgentGraph::Router.route(@chat)
  end

  private

  def add_user_message(content)
    add_message(:user, content)
  end

  def add_assistant_message(content)
    add_message(:assistant, content)
  end

  def add_message(role, content)
    Message.suppressing_turbo_broadcasts do
      @chat.messages.create!(role: role, content: content)
    end
  end
end
