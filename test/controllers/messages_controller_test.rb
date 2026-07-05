# frozen_string_literal: true

require "base64"
require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "create enqueues chat response job with text message" do
    assert_enqueued_with(job: ChatResponseJob, args: [@chat.id]) do
      post chat_messages_path(@chat), params: {
        message: { content: "こんにちは" }
      }
    end

    message = @chat.messages.where(role: :user).order(:id).last
    assert_equal "こんにちは", message.content
    assert @chat.reload.responding?
  end

  test "create accepts image attachment without text" do
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )

    assert_enqueued_with(job: ChatResponseJob, args: [@chat.id]) do
      post chat_messages_path(@chat), params: {
        message: {
          content: "",
          attachments: Rack::Test::UploadedFile.new(
            StringIO.new(png),
            "image/png",
            original_filename: "pixel.png"
          )
        }
      }
    end

    message = @chat.messages.where(role: :user).order(:id).last
    assert message.attachments.attached?
    assert_equal ChatImageAttachments::PLACEHOLDER, message.content
  end

  test "create rejects blank message without attachment" do
    assert_no_enqueued_jobs only: ChatResponseJob do
      post chat_messages_path(@chat), params: {
        message: { content: "  " }
      }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end
end
