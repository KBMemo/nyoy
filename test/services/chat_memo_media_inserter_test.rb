# frozen_string_literal: true

require "base64"
require "test_helper"

class ChatMemoMediaInserterTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    NyoyConnectionStore.clear_cache!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "asciidoc_fragment builds image macros" do
    fragment = ChatMemoMediaInserter.asciidoc_fragment(%w[01JTEST 01JOTHER])

    assert_equal "image::media:01JTEST[]\nimage::media:01JOTHER[]", fragment
  end

  test "media_ids_from_chat collects archived attachment ids" do
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
    message = @chat.messages.create!(role: :user, content: "画像付き")
    message.attachments.attach(
      io: StringIO.new(png),
      filename: "pixel.png",
      content_type: "image/png",
      metadata: { tsuzura_media_id: "01JARCHIVED" }
    )

    assert_equal ["01JARCHIVED"], ChatMemoMediaInserter.media_ids_from_chat(@chat)
  end

  test "append_media_to_memo updates memo with asciidoc append" do
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
    message = @chat.messages.create!(role: :user, content: "保存して")
    message.attachments.attach(
      io: StringIO.new(png),
      filename: "pixel.png",
      content_type: "image/png",
      metadata: { tsuzura_media_id: "01JARCHIVED" }
    )

    calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:update_memo) do |memo_ref, **kwargs|
      calls << [memo_ref, kwargs]
      { "uid" => memo_ref, "updated_at" => "2026-07-03T10:00:01Z" }
    end

    memo = { "uid" => "01JMEMO", "updated_at" => "2026-07-03T10:00:00Z", "title" => "test" }
    result = ChatMemoMediaInserter.append_media_to_memo!(fake_client, @chat, memo)

    assert_equal ["01JARCHIVED"], result["appended_media_ids"]
    assert_equal "01JMEMO", calls.first[0]
    assert_equal "asciidoc", calls.first[1][:body_format]
    assert_equal "image::media:01JARCHIVED[]", calls.first[1][:append_body]
  end

  test "append_media_to_memo skips when chat has no archived media" do
    fake_client = Object.new
    fake_client.define_singleton_method(:update_memo) { |*, **| raise "should not call" }

    memo = { "uid" => "01JMEMO", "updated_at" => "2026-07-03T10:00:00Z" }
    result = ChatMemoMediaInserter.append_media_to_memo!(fake_client, @chat, memo)

    assert_equal memo, result
  end
end
