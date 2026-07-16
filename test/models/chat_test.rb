# frozen_string_literal: true

require "base64"
require "test_helper"

class ChatTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    @png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
  end

  test "user_image_attachment_messages? detects user image attachments" do
    message = @chat.messages.create!(role: :user, content: ChatImageAttachments::PLACEHOLDER)
    message.attachments.attach(io: StringIO.new(@png), filename: "pixel.png", content_type: "image/png")

    assert @chat.user_image_attachment_messages?
  end

  test "user_image_attachment_messages? ignores assistant attachments" do
    message = @chat.messages.create!(role: :assistant, content: "画像")
    message.attachments.attach(io: StringIO.new(@png), filename: "pixel.png", content_type: "image/png")

    assert_not @chat.user_image_attachment_messages?
  end
end
