# frozen_string_literal: true

require "test_helper"

class PromptKnowledgeRetrieverTest < ActiveSupport::TestCase
  test "returns embedded prompt chunks only" do
    style_id = prompt_styles(:chojugiga).style_id
    PromptKnowledgeChunk.create!(title: "Near", body: "chojugiga emaki ink outline", kind: "style", style_ref: style_id)
    PromptKnowledgeChunk.create!(
      source: PromptKnowledgeChunk::SOURCE_MEMO,
      kind: "memo",
      external_id: "kbmemo:01J8X2K3M4N5P6Q7R8S9T0UVWX:chunk:0",
      title: "Memo",
      body: "chojugiga travel notes",
      metadata: { memo_uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX" },
      skip_auto_embed: true,
      embedding: EmbeddingClient.new.embed(input: "chojugiga travel notes")
    )

    results = PromptKnowledgeRetriever.new(limit: 2).retrieve("chojugiga emaki ink")

    assert results.all? { |chunk| chunk.source == PromptKnowledgeChunk::SOURCE_PROMPT }
  end

  test "returns embedded chunks for a query" do
    style_id = prompt_styles(:chojugiga).style_id
    PromptKnowledgeChunk.create!(title: "Near", body: "chojugiga emaki ink outline", kind: "style", style_ref: style_id)
    PromptKnowledgeChunk.create!(title: "Far", body: "photorealistic cityscape neon", kind: "style", style_ref: style_id)

    results = PromptKnowledgeRetriever.new(limit: 2).retrieve("chojugiga emaki ink")

    assert_equal 2, results.size
    assert results.all? { |chunk| chunk.embedding.present? }
  end
end
