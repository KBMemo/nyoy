# frozen_string_literal: true

require "test_helper"

class PromptRagContextTest < ActiveSupport::TestCase
  test "retrieves chunks and builds sections for a record" do
    chunk = PromptKnowledgeChunk.create!(
      title: "ChojuGiga style",
      body: "chojugiga, emaki, ink outline",
      kind: "style"
    )

    illustration = MemoIllustration.new(body: "鳥獣戯画風のウサギ", sd_model: "pony-v6")
    retriever = Class.new do
      define_method(:retrieve) { |query| PromptKnowledgeChunk.where(title: "ChojuGiga style") }
    end.new

    result = PromptRagContext.new(record: illustration, retriever: retriever).call("鳥獣戯画")

    assert_includes result[:chunk_ids], chunk.id
    assert_includes result[:chunk_section], "chojugiga"
    assert_includes result[:preset_section], "鳥獣戯画テンプレ"
  end
end
