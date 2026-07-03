# frozen_string_literal: true

require "test_helper"

class MessagesUserPartialTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "attachment image uses relative active storage path" do
    message = @chat.messages.create!(role: :user, content: "画像について")
    message.attachments.attach(
      io: StringIO.new("fake-png"),
      filename: "memo-illustration-33.png",
      content_type: "image/png"
    )

    html = render partial: "messages/user", locals: { message: message }

    assert_includes html, 'src="/rails/active_storage/'
    assert_not_includes html, "example.org"
    assert_includes html, "memo-illustration-33.png"
  end
end
