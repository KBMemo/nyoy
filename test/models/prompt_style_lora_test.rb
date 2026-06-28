# frozen_string_literal: true

require "test_helper"

class PromptStyleLoraTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert prompt_style_loras(:chojugiga_lora).valid?
  end

  test "lora is unique within a style" do
    dup = PromptStyleLora.new(
      prompt_style: prompt_styles(:chojugiga),
      lora_profile: lora_profiles(:chojugiga),
      multiplier: 0.5
    )
    assert_not dup.valid?
    assert dup.errors.key?(:lora_profile_id)
  end

  test "multiplier within range" do
    link = prompt_style_loras(:chojugiga_lora)
    link.multiplier = 3.0
    assert_not link.valid?
    assert link.errors.key?(:multiplier)
  end

  test "to_lora_entry builds api payload" do
    entry = prompt_style_loras(:chojugiga_lora).to_lora_entry
    assert_equal "ChojuGiga_Illustrious", entry["name"]
    assert_equal "chojugiga/ChojuGiga_Illustrious.safetensors", entry["path"]
    assert_in_delta 0.8, entry["multiplier"], 0.001
  end
end
