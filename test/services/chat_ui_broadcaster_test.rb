# frozen_string_literal: true

require "test_helper"

class ChatUiBroadcasterTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @message = @chat.messages.create!(role: :assistant, content: "回答")
  end

  test "assistant_content broadcasts raw text for lightweight streaming" do
    broadcasts = capture_broadcasts do
      ChatUiBroadcaster.assistant_content(@message, "### 見出し\n\n本文", seq: 3)
    end

    payload = broadcasts.last
    assert_equal "assistant_content", payload[:type]
    assert_equal @message.id, payload[:message_id]
    assert_equal 3, payload[:seq]
    assert_equal "### 見出し\n\n本文", payload[:text]
    assert_nil payload[:html]
  end

  test "assistant_finalized broadcasts rendered message html" do
    broadcasts = capture_broadcasts do
      ChatUiBroadcaster.assistant_finalized(@message, content: "**完了**", thinking_text: nil, seq: 4)
    end

    payload = broadcasts.last
    assert_equal "assistant_finalized", payload[:type]
    assert_equal @message.id, payload[:message_id]
    assert_equal 4, payload[:seq]
    assert_includes payload[:html], "<strong>完了</strong>"
  end

  test "form_updated broadcasts replacement form html" do
    broadcasts = capture_broadcasts do
      ChatUiBroadcaster.form_updated(@chat)
    end

    payload = broadcasts.last
    assert_equal "form_updated", payload[:type]
    assert_includes payload[:html], 'id="new_message"'
  end

  private

  def capture_broadcasts
    broadcasts = []
    original = ChatChannel.method(:broadcast_to)
    ChatChannel.singleton_class.define_method(:broadcast_to) do |chat, payload|
      broadcasts << payload.merge(chat: chat)
    end

    yield
    broadcasts
  ensure
    ChatChannel.singleton_class.define_method(:broadcast_to, original)
  end
end
