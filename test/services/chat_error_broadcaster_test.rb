# frozen_string_literal: true

require "test_helper"

class ChatErrorBroadcasterTest < ActiveSupport::TestCase
  include ActionView::RecordIdentifier

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "creates chat error message for context length failures" do
    error = RubyLLM::BadRequestError.new(
      nil,
      "request (16386 tokens) exceeds the available context size (16384 tokens), try increasing it"
    )

    message = ChatErrorBroadcaster.fail!(@chat, error)

    assert message.chat_error?
    assert_includes message.chat_error_message, "会話が長すぎます"
    assert_includes message.chat_error_message, "16386 tokens"
  end

  test "removes blank assistant message before creating error" do
    @chat.messages.create!(role: :assistant, content: "")
    error = RubyLLM::ServerError.new(nil, "server error")

    ChatErrorBroadcaster.fail!(@chat, error)

    assert_equal 1, @chat.messages.where(role: :assistant).count
    assert @chat.messages.where(role: :assistant).last.chat_error?
  end

  test "renders chat error partial" do
    message = @chat.messages.create!(
      role: :assistant,
      content: "#{ChatErrorBroadcaster::ERROR_PREFIX}テストエラー"
    )

    assert_equal "messages/chat_error", message.to_partial_path
  end
end
