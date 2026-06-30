# frozen_string_literal: true

require "test_helper"

class SdPromptTokenizerTest < ActiveSupport::TestCase
  test "counts CLIP tokens for a simple prompt" do
    assert_equal 5, SdPromptTokenizer.count("a photo of a cat")
  end

  test "returns zero for blank text" do
    assert_equal 0, SdPromptTokenizer.count("")
    assert_equal 0, SdPromptTokenizer.count("   ")
  end

  test "labels include limit" do
    assert_equal "5 / 75", SdPromptTokenizer.label("a photo of a cat")
  end

  test "detects over limit prompts" do
    long_prompt = ("watercolor painting, " * 40).strip
    assert SdPromptTokenizer.over_limit?(long_prompt)
  end
end
