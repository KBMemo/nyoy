# frozen_string_literal: true

require "test_helper"

class ChatContextBuilderTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @original_turns = Rails.application.config.x.nyoy.chat_context_turns
    Rails.application.config.x.nyoy.chat_context_turns = 1
  end

  teardown do
    Rails.application.config.x.nyoy.chat_context_turns = @original_turns
  end

  test "keeps recent turn and summarizes older turns" do
    @chat.messages.create!(role: :user, content: "old question")
    @chat.messages.create!(role: :assistant, content: "old answer")
    @chat.messages.create!(role: :user, content: "new question")
    @chat.messages.create!(role: :assistant, content: "new answer")

    result = ChatContextBuilder.build(@chat)

    assert_equal 1, result.summarized_turns
    assert_includes result.summary, "old question"
    assert result.messages.any? { |message| message.content == "new question" }
    assert_not result.messages.any? { |message| message.content == "old question" }

    @chat.reload
    assert @chat.context_summary.present?
    old_boundary = @chat.messages.order(:id).second.id
    assert_equal old_boundary, @chat.context_summary_until_message_id

    cached = ChatContextBuilder.build(@chat)
    assert_equal @chat.context_summary, cached.summary
  end
end
