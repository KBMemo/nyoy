# frozen_string_literal: true

require "test_helper"

class ChatContextStatsTest < ActiveSupport::TestCase
  setup do
    model = Model.create!(
      provider: "test",
      model_id: "chat-context-stats-test",
      name: "Chat Context Stats Test",
      context_window: 8192
    )
    @chat = Chat.create!(model: model)
  end

  test "estimates tokens for chat messages" do
    @chat.messages.create!(role: :user, content: "a" * 400)

    stats = ChatContextStats.for(@chat)

    assert stats.estimated_tokens.positive?
    assert_equal 8192, stats.context_window
  end
end
