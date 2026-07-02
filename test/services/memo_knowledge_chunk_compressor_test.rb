# frozen_string_literal: true

require "test_helper"

class MemoKnowledgeChunkCompressorTest < ActiveSupport::TestCase
  test "keeps keyword-related lines" do
    chunk = PromptKnowledgeChunk.new(
      title: "開発メモ",
      body: "前置き\n\nRails の設定\n\n無関係な雑記\n\npgvector 索引",
      metadata: { memo_uid: "01J8X2K3M4N5P6Q7R8S9T0UVWX" }
    )

    compressed = MemoKnowledgeChunkCompressor.new(max_chars: 800, llm_enabled: false)
                                              .compress([chunk], query: "pgvector 設定").first

    assert_includes compressed.body, "pgvector"
    assert_includes compressed.body, "Rails"
    assert_not_includes compressed.body, "無関係"
  end
end
