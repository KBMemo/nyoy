# frozen_string_literal: true

require "test_helper"

class ChatMessagesBroadcasterTest < ActiveSupport::TestCase
  include ActionView::RecordIdentifier

  setup do
    ChatModelCatalog.seed!
    @chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
  end

  test "sync replaces messages container with id-ordered messages" do
    user = @chat.messages.create!(role: :user, content: "質問")
    assistant = @chat.messages.create!(role: :assistant, content: "回答")

    broadcasts = []
    original = Turbo::StreamsChannel.method(:broadcast_replace_to)
    Turbo::StreamsChannel.singleton_class.define_method(:broadcast_replace_to) do |*args, **kwargs|
      broadcasts << { args: args, kwargs: kwargs }
    end

    begin
      ChatMessagesBroadcaster.sync!(@chat)
    ensure
      Turbo::StreamsChannel.singleton_class.define_method(:broadcast_replace_to, original)
    end

    assert_equal 1, broadcasts.size
    assert_equal [ "chat_#{@chat.id}" ], broadcasts.first[:args]
    assert_equal "messages", broadcasts.first[:kwargs][:target]
    assert_equal "chats/messages", broadcasts.first[:kwargs][:partial]

    html = ApplicationController.render(
      partial: broadcasts.first[:kwargs][:partial],
      locals: broadcasts.first[:kwargs][:locals]
    )

    assert_match(/#{dom_id(user)}/, html)
    assert_match(/#{dom_id(assistant)}/, html)
    assert_operator html.index(dom_id(user)), :<, html.index(dom_id(assistant))
  end
end
