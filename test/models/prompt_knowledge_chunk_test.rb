# frozen_string_literal: true

require "test_helper"

class PromptKnowledgeChunkTest < ActiveSupport::TestCase
  test "embeds after save" do
    chunk = PromptKnowledgeChunk.create!(
      title: "Test chunk",
      body: "chojugiga, ink outline",
      kind: "style",
      style_ref: prompt_styles(:chojugiga).style_id
    )

    chunk.reload
    assert chunk.embedding.present?
    assert_equal Rails.application.config.x.nyoy.embedding_dimensions, chunk.embedding.length
  end

  test "requires style_ref for style kind" do
    chunk = PromptKnowledgeChunk.new(title: "Test", body: "body", kind: "style")

    assert_not chunk.valid?
    assert_includes chunk.errors[:style_ref], "can't be blank"
  end

  test "re-embeds when body changes" do
    chunk = prompt_knowledge_chunks(:chojugiga_style)
    chunk.update!(body: "#{chunk.body}\nupdated")

    chunk.reload
    assert chunk.embedding.present?
  end
end
