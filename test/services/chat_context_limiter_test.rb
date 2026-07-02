# frozen_string_literal: true

require "test_helper"

class ChatContextLimiterTest < ActiveSupport::TestCase
  MessageStub = Struct.new(:role, :content, keyword_init: true)

  test "returns all messages when max_turns is zero" do
    messages = build_messages

    result = ChatContextLimiter.trim(messages, max_turns: 0)

    assert_equal messages, result
  end

  test "keeps system messages and only the last turn" do
    messages = [
      msg(:system, "instructions"),
      msg(:user, "first"),
      msg(:assistant, "reply 1"),
      msg(:user, "second"),
      msg(:assistant, "reply 2")
    ]

    result = ChatContextLimiter.trim(messages, max_turns: 1)

    assert_equal [ "instructions" ], result.select { |m| m.role == :system }.map(&:content)
    assert_equal [ "second", "reply 2" ], result.reject { |m| m.role == :system }.map(&:content)
  end

  test "keeps tool messages in the same turn as the user request" do
    messages = [
      msg(:user, "older"),
      msg(:assistant, "old reply"),
      msg(:user, "search this"),
      msg(:assistant, ""),
      msg(:tool, "tool output"),
      msg(:assistant, "final reply")
    ]

    result = ChatContextLimiter.trim(messages, max_turns: 1)

    assert_equal(
      [ "search this", "", "tool output", "final reply" ],
      result.map(&:content)
    )
  end

  test "keeps the last two turns" do
    messages = build_messages

    result = ChatContextLimiter.trim(messages, max_turns: 2)

    assert_equal [ "instructions" ], result.select { |m| m.role == :system }.map(&:content)
    assert_equal(
      [ "first", "reply 1", "second", "reply 2" ],
      result.reject { |m| m.role == :system }.map(&:content)
    )
  end

  private

  def build_messages
    [
      msg(:system, "instructions"),
      msg(:user, "first"),
      msg(:assistant, "reply 1"),
      msg(:user, "second"),
      msg(:assistant, "reply 2")
    ]
  end

  def msg(role, content)
    MessageStub.new(role: role, content: content)
  end
end
