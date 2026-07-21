# frozen_string_literal: true

require "test_helper"

class LlmUsageCatalogTest < ActiveSupport::TestCase
  test "defines unique stable usage keys" do
    keys = LlmUsageCatalog.keys

    assert_equal keys.uniq, keys
    assert_includes keys, "chat.default"
    assert_includes keys, "agent.final_answer"
    assert_includes keys, "vision.image_understanding"
    assert_includes keys, "embedding.memo_knowledge"
  end

  test "declares required capabilities for each usage" do
    LlmUsageCatalog.all.each do |definition|
      assert_not_empty definition.capabilities
      assert_empty definition.capabilities - LlmUsageCatalog::CAPABILITIES
    end

    assert_equal %i[text_generation tool_calling], LlmUsageCatalog.required_capabilities("chat.default")
    assert_equal %i[text_generation vision], LlmUsageCatalog.required_capabilities("vision.image_understanding")
    assert_equal %i[embedding], LlmUsageCatalog.required_capabilities("embedding.memo_knowledge")
  end

  test "looks up usages by capability" do
    keys = LlmUsageCatalog.supporting(:vision).map(&:key)

    assert_equal [ "vision.image_understanding" ], keys
    assert_raises(ArgumentError) { LlmUsageCatalog.supporting(:unknown) }
  end

  test "rejects unknown usage keys" do
    assert_raises(KeyError) { LlmUsageCatalog.fetch("unknown") }
  end
end
