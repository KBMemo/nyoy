# frozen_string_literal: true

require "base64"
require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "chat error message uses dedicated partial" do
    message = @chat.messages.create!(
      role: :assistant,
      content: "#{ChatErrorBroadcaster::ERROR_PREFIX}失敗しました"
    )

    assert_equal "messages/chat_error", message.to_partial_path
    assert_equal "失敗しました", message.chat_error_message
  end

  test "broadcast_refresh replaces the full assistant bubble" do
    message = @chat.messages.create!(role: :assistant, content: "**done**")

    with_chat_ui_capture(:assistant_finalized) do |broadcasts|
      message.broadcast_refresh!

      assert_equal 1, broadcasts.size
      assert_equal message, broadcasts.first.first.first
      assert_equal "**done**", broadcasts.first.second[:content]
    end
  end

  test "broadcast_refresh can override streamed body and thinking text" do
    message = @chat.messages.create!(role: :assistant, content: "")

    with_chat_ui_capture(:assistant_finalized) do |broadcasts|
      message.broadcast_refresh!(content: "1行目\n2行目", thinking_text: "考え")

      assert_equal "1行目\n2行目", broadcasts.first.second[:content]
      assert_equal "考え", broadcasts.first.second[:thinking_text]
    end
  end

  test "broadcast_message_updated is suppressed while chat is responding" do
    @chat.update!(response_state: "running")
    message = @chat.messages.create!(role: :assistant, content: "途中")

    with_chat_ui_capture(:message_upsert) do |broadcasts|
      message.update!(content: "更新")

      assert_empty broadcasts
    end
  ensure
    @chat.update!(response_state: "idle")
  end

  test "tool call assistant update is upserted while chat is responding" do
    @chat.update!(response_state: "running")
    message = @chat.messages.create!(role: :assistant, content: "")
    message.tool_calls_association.create!(
      tool_call_id: "call_test",
      name: "fetch_url",
      arguments: { "url" => "https://example.com" }
    )

    with_chat_ui_capture(:message_upsert) do |broadcasts|
      message.update!(content: "")

      assert_equal 1, broadcasts.size
      assert_equal message, broadcasts.first.first.first
    end
  ensure
    @chat.update!(response_state: "idle")
  end

  test "broadcast_rendered_content replaces content with markdown html" do
    message = @chat.messages.create!(role: :assistant, content: "**done**")

    with_chat_ui_capture(:assistant_content) do |broadcasts|
      message.broadcast_rendered_content!("### 見出し\n\n**太字**")

      assert_equal 1, broadcasts.size
      assert_equal message, broadcasts.first.first.first
      assert_equal "### 見出し\n\n**太字**", broadcasts.first.first.second
    end
  end

  test "broadcast_rendered_thinking replaces thinking section" do
    message = @chat.messages.create!(role: :assistant, content: "回答")

    with_chat_ui_capture(:assistant_thinking) do |broadcasts|
      message.broadcast_rendered_thinking!("考え中")

      assert_equal 1, broadcasts.size
      assert_equal message, broadcasts.first.first.first
      assert_equal "考え中", broadcasts.first.first.second
    end
  end

  test "to_llm adds optional analyze_image notice for attachments" do
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
    message = @chat.messages.create!(role: :user, content: ChatImageAttachments::PLACEHOLDER)
    message.attachments.attach(
      io: StringIO.new(png),
      filename: "pixel.png",
      content_type: "image/png"
    )

    llm_message = message.to_llm

    assert_includes llm_message.content, "analyze_image"
    assert_includes llm_message.content, "1 枚添付"
    assert_includes llm_message.content, "必要なときだけ"
    assert_includes llm_message.content, "web_search"
  end

  private

  def with_chat_ui_capture(method_name)
    calls = []
    original = ChatUiBroadcaster.method(method_name)
    ChatUiBroadcaster.singleton_class.define_method(method_name) do |*args, **kwargs|
      calls << [ args, kwargs ]
    end

    yield calls
  ensure
    ChatUiBroadcaster.singleton_class.define_method(method_name, original)
  end
end
