# frozen_string_literal: true

require "test_helper"

class GenerationPresetTest < ActiveSupport::TestCase
  test "parses loras json" do
    preset = generation_presets(:chojugiga)
    assert_equal 1, preset.loras_array.size
    assert_equal "ChojuGiga_Illustrious", preset.loras_array.first["name"]
  end

  test "builds loras payload for sd-server" do
    preset = generation_presets(:chojugiga)
    payload = preset.loras_for_api

    assert_equal 1, payload.size
    assert_equal "chojugiga/ChojuGiga_Illustrious.safetensors", payload.first["path"]
    assert_in_delta 0.8, payload.first["multiplier"]
  end

  test "applies settings to image generation" do
    preset = generation_presets(:chojugiga)
    preset.update!(default_negative_prompt: "text, watermark")
    generation = ImageGeneration.new(japanese_prompt: "test")

    preset.apply_to(generation)

    assert_equal preset, generation.generation_preset
    assert_equal preset.prompt_skill, generation.prompt_skill
    assert_equal 768, generation.width
    assert_equal "euler_a", generation.sampler_name
    assert generation.vae_tiling
    assert_includes generation.negative_prompt, "text"
    assert_includes generation.negative_prompt, "watermark"
  end

  test "only one default preset" do
    first = GenerationPreset.create!(
      name: "Preset A",
      sd_model: "flat2d",
      width: 512,
      height: 512,
      steps: 20,
      cfg_scale: 7.0,
      sampler_name: "euler_a",
      vae_tiling: false,
      loras: "[]",
      default: true
    )
    second = GenerationPreset.create!(
      name: "Preset B",
      sd_model: "pony-v6",
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      vae_tiling: true,
      loras: "[]",
      default: true
    )

    assert_not first.reload.default?
    assert second.reload.default?
  end
end
