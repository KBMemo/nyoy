# frozen_string_literal: true

require "test_helper"

class PromptKnowledgeRetrieverTest < ActiveSupport::TestCase
  test "returns embedded chunks for a query" do
    style_id = prompt_styles(:chojugiga).style_id
    PromptKnowledgeChunk.create!(title: "Near", body: "chojugiga emaki ink outline", kind: "style", style_ref: style_id)
    PromptKnowledgeChunk.create!(title: "Far", body: "photorealistic cityscape neon", kind: "style", style_ref: style_id)

    results = PromptKnowledgeRetriever.new(limit: 2).retrieve("chojugiga emaki ink")

    assert_equal 2, results.size
    assert results.all? { |chunk| chunk.embedding.present? }
  end
end
