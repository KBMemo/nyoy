# frozen_string_literal: true

require "test_helper"

class PromptSkillDraftStoreTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @original_cache = Rails.cache
    Rails.cache = @cache
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "writes and fetches draft once" do
    draft = {
      name: "テスト",
      body: "x" * 5000,
      default_negative_prompt: "low quality",
      source_chunk_ids: [1, 2]
    }

    token = PromptSkillDraftStore.write(draft)
    fetched = PromptSkillDraftStore.fetch(token)

    assert_equal "テスト", fetched["name"]
    assert_equal 5000, fetched["body"].length
    assert_nil PromptSkillDraftStore.fetch(token)
  end
end
