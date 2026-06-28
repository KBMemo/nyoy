# frozen_string_literal: true

require "test_helper"

class PromptSkillDraftGeneratorTest < ActiveSupport::TestCase
  test "builds skill draft from knowledge chunks" do
    chunk = PromptKnowledgeChunk.create!(
      title: "ChojuGiga style",
      body: "chojugiga, emaki, ink outline",
      kind: "style"
    )

    llama_response = {
      "choices" => [{
        "message" => {
          "content" => {
            name: "鳥獣戯画プロンプト (JSON)",
            body: "# Role\nYou write JSON plans for chojugiga style.",
            default_negative_prompt: "text, watermark"
          }.to_json
        }
      }]
    }

    client = Class.new do
      define_method(:initialize) { |**| }
      define_method(:chat) { |**| llama_response }
    end.new

    draft = PromptSkillDraftGenerator.new(client: client).call(chunks: [chunk])

    assert_equal "鳥獣戯画プロンプト (JSON)", draft[:name]
    assert_includes draft[:body], "JSON plans"
    assert_equal "text, watermark", draft[:default_negative_prompt]
    assert_equal [chunk.id], draft[:source_chunk_ids]
  end
end
