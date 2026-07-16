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
    refute decision.memo_update?
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
    refute decision.memo_update?
    assert_equal "strong", decision.intent_decision[:reason]
  end

  test "routes image attachment only turn to image understanding graph" do
    message = add_user_message(ChatImageAttachments::PLACEHOLDER)
    message.attachments.attach(io: StringIO.new("png"), filename: "pixel.png", content_type: "image/png")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::ImageUnderstandingGraph::NAME, decision.graph_name
    assert_equal AgentGraph::ImageUnderstandingGraphRunner, decision.runner
    assert decision.image_understanding?
    refute decision.memo_write?
    refute decision.memo_update?
    refute decision.research?
    assert_equal "attachment_only", decision.intent_decision[:reason]
  end

  test "routes image reference turn to image understanding graph" do
    message = add_user_message("この画像には何が写っていますか？")
    message.attachments.attach(io: StringIO.new("png"), filename: "pixel.png", content_type: "image/png")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::ImageUnderstandingGraph::NAME, decision.graph_name
    assert_equal "image_reference", decision.intent_decision[:reason]
  end

  test "memo write is evaluated before research" do
    add_user_message("この回答を徒然に保存して。出典も残して")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::MemoWriteGraph::NAME, decision.graph_name
  end

  test "memo write is evaluated before image understanding" do
    message = add_user_message("この内容をメモに保存して")
    message.attachments.attach(io: StringIO.new("png"), filename: "pixel.png", content_type: "image/png")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::MemoWriteGraph::NAME, decision.graph_name
  end

  test "memo update is evaluated before memo write" do
    add_user_message("メモ 42 に追記して\n追加本文")

    decision = AgentGraph::Router.route(@chat)

    assert_equal AgentGraph::MemoUpdateGraph::NAME, decision.graph_name
    assert_equal AgentGraph::MemoUpdateGraphRunner, decision.runner
    assert decision.memo_update?
    refute decision.memo_write?
    refute decision.research?
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

  test "returns nil for image generation request with attachment" do
    message = add_user_message("この画像を参考にイラストを作って")
    message.attachments.attach(io: StringIO.new("png"), filename: "pixel.png", content_type: "image/png")

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
