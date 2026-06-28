# frozen_string_literal: true

require "test_helper"

class EmbeddingInputTest < ActiveSupport::TestCase
  setup do
    @original = Rails.application.config.x.nyoy.embedding_max_chars
    Rails.application.config.x.nyoy.embedding_max_chars = 100
  end

  teardown do
    Rails.application.config.x.nyoy.embedding_max_chars = @original
  end

  test "truncates long text" do
    text = "a" * 200

    assert_equal 100, EmbeddingInput.truncate(text).length
    assert EmbeddingInput.truncated?(text)
  end
end
