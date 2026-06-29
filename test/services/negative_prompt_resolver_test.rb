# frozen_string_literal: true

require "test_helper"

class NegativePromptResolverTest < ActiveSupport::TestCase
  test "merge deduplicates comma-separated tags" do
    result = NegativePromptResolver.merge("text, watermark", "watermark, blurry")

    assert_equal "text, watermark, blurry", result
  end

  test "for_generation returns supplemental negative on record" do
    generation = ImageGeneration.new(negative_prompt: "extra artifact")

    assert_equal "extra artifact", NegativePromptResolver.for_generation(generation)
  end

  test "merge returns blank when all inputs are blank" do
    assert_equal "", NegativePromptResolver.merge
  end
end
