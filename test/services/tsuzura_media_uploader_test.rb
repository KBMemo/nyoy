# frozen_string_literal: true

require "base64"
require "test_helper"

class TsuzuraMediaUploaderTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    NyoyConnectionStore.clear_cache!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "archives attachment metadata when upload succeeds" do
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
    message = @chat.messages.create!(role: :user, content: "test")
    message.attachments.attach(
      io: StringIO.new(png),
      filename: "pixel.png",
      content_type: "image/png"
    )
    attachment = message.attachments.first

    fake_client = Object.new
    fake_client.define_singleton_method(:upload_batch) do |**|
      {
        "items" => [{ "id" => "01JARCHIVED", "original_filename" => "pixel.png" }]
      }
    end
    original = TsuzuraMediaUploader.method(:client)
    TsuzuraMediaUploader.define_singleton_method(:client) { fake_client }

    TsuzuraMediaUploader.archive_attachment!(attachment)

    assert_equal "01JARCHIVED", attachment.reload.metadata["tsuzura_media_id"]
  ensure
    TsuzuraMediaUploader.define_singleton_method(:client, original)
  end

  test "skips when tsuzura is not configured" do
    service_connections(:tsuzura).update!(api_token: nil, enabled: false)
    NyoyConnectionStore.clear_cache!

    message = @chat.messages.create!(role: :user, content: "test")
    message.attachments.attach(
      io: StringIO.new("x"),
      filename: "pixel.png",
      content_type: "image/png"
    )
    attachment = message.attachments.first

    TsuzuraMediaUploader.archive_attachment!(attachment)

    assert_nil attachment.reload.metadata["tsuzura_media_id"]
  end
end
