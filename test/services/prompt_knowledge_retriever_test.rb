# frozen_string_literal: true

require "test_helper"

class PromptKnowledgeRetrieverTest < ActiveSupport::TestCase
  test "returns embedded chunks for a query" do
    PromptKnowledgeChunk.create!(title: "Near", body: "chojugiga emaki ink outline", kind: "style")
    PromptKnowledgeChunk.create!(title: "Far", body: "photorealistic cityscape neon", kind: "style")

    results = PromptKnowledgeRetriever.new(limit: 2).retrieve("chojugiga emaki ink")

    assert_equal 2, results.size
    assert results.all? { |chunk| chunk.embedding.present? }
  end
end
