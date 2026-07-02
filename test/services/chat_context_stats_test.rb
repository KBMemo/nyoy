# frozen_string_literal: true

require "test_helper"

class ChatContextStatsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "estimates tokens for chat messages" do
    @chat.messages.create!(role: :user, content: "a" * 400)

    stats = ChatContextStats.for(@chat)

    assert stats.estimated_tokens.positive?
    assert_equal 8192, stats.context_window
  end
end
