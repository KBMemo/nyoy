# frozen_string_literal: true

require "test_helper"

class PromptKnowledgeChunkEmbedderTest < ActiveSupport::TestCase
  setup do
    @original = Rails.application.config.x.nyoy.embedding_max_chars
    Rails.application.config.x.nyoy.embedding_max_chars = 50
  end

  teardown do
    Rails.application.config.x.nyoy.embedding_max_chars = @original
  end

  test "sends truncated text to embedding client" do
    captured = nil
    client = Class.new do
      define_method(:embed) do |input:|
        captured = input
        Array.new(Rails.application.config.x.nyoy.embedding_dimensions, 0.1)
      end
    end.new

    PromptKnowledgeChunkEmbedder.new(client: client).embed_text("x" * 200)

    assert_equal 50, captured.length
  end
end
