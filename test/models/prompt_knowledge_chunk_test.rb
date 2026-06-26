# frozen_string_literal: true

require "test_helper"

class PromptKnowledgeChunkTest < ActiveSupport::TestCase
  test "embeds after save" do
    chunk = PromptKnowledgeChunk.create!(
      title: "Test chunk",
      body: "chojugiga, ink outline",
      kind: "style"
    )

    chunk.reload
    assert chunk.embedding.present?
    assert_equal Rails.application.config.x.nyoy.embedding_dimensions, chunk.embedding.length
  end

  test "re-embeds when body changes" do
    chunk = prompt_knowledge_chunks(:chojugiga_style)
    chunk.update!(body: "#{chunk.body}\nupdated")

    chunk.reload
    assert chunk.embedding.present?
  end
end
