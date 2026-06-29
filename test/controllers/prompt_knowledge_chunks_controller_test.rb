# frozen_string_literal: true

require "test_helper"

class PromptKnowledgeChunksControllerTest < ActionDispatch::IntegrationTest
  test "create requires style_ref for style kind" do
    assert_no_difference -> { PromptKnowledgeChunk.count } do
      post prompt_knowledge_chunks_path, params: {
        prompt_knowledge_chunk: {
          title: "新しい画風",
          kind: "style",
          body: "test body"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create with style_ref succeeds" do
    assert_difference -> { PromptKnowledgeChunk.count }, 1 do
      post prompt_knowledge_chunks_path, params: {
        prompt_knowledge_chunk: {
          title: "新しい画風",
          kind: "style",
          style_ref: prompt_styles(:chojugiga).style_id,
          body: "test body"
        }
      }
    end

    assert_redirected_to prompt_knowledge_chunk_path(PromptKnowledgeChunk.order(:id).last)
  end
end
