# frozen_string_literal: true

require "test_helper"

class AgentGraphUserTurnResolverTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "uses latest user content when explicit content is absent" do
    @chat.messages.create!(role: :user, content: "直近の質問")

    content = AgentGraph::UserTurnResolver.call(
      chat: @chat,
      explicit_content: nil,
      required_label: "user question"
    )

    assert_equal "直近の質問", content
  end

  test "appends explicit content when it differs from latest user content" do
    @chat.messages.create!(role: :user, content: "古い質問")

    content = AgentGraph::UserTurnResolver.call(
      chat: @chat,
      explicit_content: " 新しい質問 ",
      required_label: "user question"
    )

    assert_equal "新しい質問", content
    assert_equal "新しい質問", @chat.messages.where(role: :user).order(:id).last.content
  end

  test "does not duplicate explicit content when it matches latest user content" do
    @chat.messages.create!(role: :user, content: "同じ質問")

    assert_no_difference -> { @chat.messages.count } do
      AgentGraph::UserTurnResolver.call(
        chat: @chat,
        explicit_content: "同じ質問",
        required_label: "user question"
      )
    end
  end

  test "raises when no content is available" do
    error = assert_raises(ArgumentError) do
      AgentGraph::UserTurnResolver.call(
        chat: @chat,
        explicit_content: nil,
        required_label: "user instruction"
      )
    end

    assert_equal "user instruction required", error.message
  end
end
