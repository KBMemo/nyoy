# frozen_string_literal: true

require "test_helper"

class AgentGraphAssistantMessagePublisherTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "creates and broadcasts assistant message" do
    message = nil

    payloads = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      message = AgentGraph::AssistantMessagePublisher.call(
        @chat,
        content: "回答",
        thinking_text: "思考"
      )
    end

    assert_equal %w[message_upsert approval_panel], payloads.map { |payload| payload["type"] }
    assert_equal "assistant", message.role.to_s
    assert_equal "回答", message.content
    assert_equal "思考", message.thinking_text
    assert_equal message, @chat.messages.where(role: :assistant).order(:id).last
  end

  test "broadcasts truncation notice when truncated" do
    message = nil

    payloads = capture_broadcasts(ChatChannel.broadcasting_for(@chat)) do
      message = AgentGraph::AssistantMessagePublisher.call(
        @chat,
        content: "途中まで",
        truncated: true
      )
    end

    assert_includes payloads.map { |payload| payload["type"] }, "approval_panel"
    assert_operator payloads.count { |payload| payload["type"] == "message_upsert" }, :>=, 2
    assert message.truncated?
  end
end
