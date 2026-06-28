# frozen_string_literal: true

require "test_helper"

class PromptKnowledgeChunksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @chunk = prompt_knowledge_chunks(:chojugiga_style)
    @cache = ActiveSupport::Cache::MemoryStore.new
    @original_cache = Rails.cache
    Rails.cache = @cache
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "generate_skill redirects to new prompt skill with draft in session" do
    draft = {
      name: "テストスキル",
      body: "system prompt body",
      default_negative_prompt: "low quality",
      source_chunk_ids: [@chunk.id]
    }

    original_new = PromptSkillDraftGenerator.method(:new)
    fake_generator = Class.new do
      define_method(:call) { |**| draft }
    end

    PromptSkillDraftGenerator.define_singleton_method(:new) { |**| fake_generator.new }
    begin
      post generate_skill_prompt_knowledge_chunks_path, params: { chunk_ids: [@chunk.id], output_kind: "json_plan" }

      assert_redirected_to new_prompt_skill_path
      follow_redirect!
      assert_match "テストスキル", response.body
      assert_match "system prompt body", response.body
    ensure
      PromptSkillDraftGenerator.singleton_class.send(:define_method, :new, original_new)
    end
  end

  test "generate_skill requires selected chunks" do
    post generate_skill_prompt_knowledge_chunks_path, params: { chunk_ids: [""] }

    assert_redirected_to prompt_knowledge_chunks_path
    follow_redirect!
    assert_match "1件以上", response.body
  end
end
