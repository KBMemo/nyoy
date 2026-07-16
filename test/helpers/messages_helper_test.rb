# frozen_string_literal: true

require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  test "llama cache label tolerates messages without migrated columns" do
    message = Object.new
    message.define_singleton_method(:has_attribute?) { |_name| false }

    assert_nil chat_message_llama_cache_label(message)
  end

  test "token label tolerates messages without migrated columns" do
    message = Object.new
    message.define_singleton_method(:has_attribute?) { |_name| false }

    assert_equal "", chat_message_token_label(message)
  end
end
