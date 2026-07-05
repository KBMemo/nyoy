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

  test "broadcast_rendered_content replaces content with markdown html" do
    message = @chat.messages.create!(role: :assistant, content: "**done**")
    broadcasts = []
    message.define_singleton_method(:broadcast_replace_to) do |*, **kwargs|
      broadcasts << kwargs
    end

    message.broadcast_rendered_content!("### 見出し\n\n**太字**")

    assert_equal 1, broadcasts.size
    assert_equal "message_#{message.id}_content", broadcasts.first[:target]
    assert_includes broadcasts.first[:html], "<h3"
    assert_includes broadcasts.first[:html], "<strong>太字</strong>"
  end

  test "broadcast_rendered_thinking replaces thinking section" do
    message = @chat.messages.create!(role: :assistant, content: "回答")
    broadcasts = []
    message.define_singleton_method(:broadcast_replace_to) do |*, **kwargs|
      broadcasts << kwargs
    end

    message.broadcast_rendered_thinking!("考え中")

    assert_equal 1, broadcasts.size
    assert_equal "message_#{message.id}_thinking_section", broadcasts.first[:target]
    assert_equal "messages/thinking_section", broadcasts.first[:partial]
    assert_equal "考え中", broadcasts.first[:locals][:text]
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
end
