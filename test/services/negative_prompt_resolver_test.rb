# frozen_string_literal: true

require "test_helper"

class NegativePromptResolverTest < ActiveSupport::TestCase
  test "merges skill and preset defaults without duplicates" do
    skill = PromptSkill.new(default_negative_prompt: "text, watermark, low quality")
    preset = GenerationPreset.new(default_negative_prompt: "text, blurry, low quality")

    result = NegativePromptResolver.base(skill: skill, preset: preset)

    assert_equal "text, watermark, low quality, blurry", result
  end

  test "appends supplemental tags to fixed defaults" do
    skill = PromptSkill.new(default_negative_prompt: "text, watermark")
    preset = GenerationPreset.new(default_negative_prompt: "blurry")

    result = NegativePromptResolver.resolve(supplemental: "extra artifact", skill: skill, preset: preset)

    assert_equal "text, watermark, blurry, extra artifact", result
  end

  test "returns supplemental tags when fixed defaults are blank" do
    result = NegativePromptResolver.resolve(supplemental: "custom only")

    assert_equal "custom only", result
  end

  test "returns blank when all inputs are blank" do
    assert_equal "", NegativePromptResolver.resolve
  end
end
