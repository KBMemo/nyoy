# frozen_string_literal: true

require "test_helper"

class NegativePromptResolverTest < ActiveSupport::TestCase
  test "merges skill and preset defaults without duplicates" do
    skill = PromptSkill.new(default_negative_prompt: "text, watermark, low quality")
    preset = GenerationPreset.new(default_negative_prompt: "text, blurry, low quality")

    result = NegativePromptResolver.resolve(skill: skill, preset: preset)

    assert_equal "text, watermark, low quality, blurry", result
  end

  test "appends user tags to defaults" do
    skill = PromptSkill.new(default_negative_prompt: "text, watermark")
    preset = GenerationPreset.new(default_negative_prompt: "blurry")

    result = NegativePromptResolver.resolve(user: "extra artifact", skill: skill, preset: preset)

    assert_equal "text, watermark, blurry, extra artifact", result
  end

  test "returns user tags when defaults are blank" do
    result = NegativePromptResolver.resolve(user: "custom only")

    assert_equal "custom only", result
  end

  test "returns blank when all inputs are blank" do
    assert_equal "", NegativePromptResolver.resolve
  end
end
