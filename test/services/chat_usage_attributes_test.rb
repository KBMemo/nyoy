# frozen_string_literal: true

require "test_helper"

class ChatUsageAttributesTest < ActiveSupport::TestCase
  test "extracts openai compatible usage details" do
    attrs = ChatUsageAttributes.from(
      "usage" => {
        "prompt_tokens" => 100,
        "completion_tokens" => 20,
        "prompt_tokens_details" => {
          "cached_tokens" => 80,
          "cache_creation_tokens" => 10
        }
      }
    )

    assert_equal 100, attrs[:input_tokens]
    assert_equal 20, attrs[:output_tokens]
    assert_equal 80, attrs[:cached_tokens]
    assert_equal 10, attrs[:cache_creation_tokens]
  end

  test "extracts usage from chunk method" do
    chunk = Object.new
    chunk.define_singleton_method(:usage) do
      {
        "prompt_tokens" => "12",
        "completion_tokens" => "3"
      }
    end

    attrs = ChatUsageAttributes.from(chunk)

    assert_equal 12, attrs[:input_tokens]
    assert_equal 3, attrs[:output_tokens]
  end
end
