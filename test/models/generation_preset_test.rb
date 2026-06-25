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

  test "apply_draft_to copies draft settings to image generation" do
    preset = generation_presets(:chojugiga)
    preset.update!(default_negative_prompt: "text, watermark")
    generation = ImageGeneration.new(japanese_prompt: "test")

    preset.apply_draft_to(generation)

    assert_equal preset, generation.generation_preset
    assert_equal preset.prompt_skill, generation.prompt_skill
    assert_equal 768, generation.width
    assert_equal "euler_a", generation.sampler_name
    assert generation.vae_tiling
    assert_equal 4, generation.draft_batch_size
    assert_includes generation.negative_prompt, "text"
    assert_includes generation.negative_prompt, "watermark"
  end

  test "apply_refine_to copies refine settings to image generation" do
    preset = generation_presets(:chojugiga_refine)
    generation = ImageGeneration.new(japanese_prompt: "test")

    preset.apply_refine_to(generation)

    assert_equal preset, generation.refine_preset
    assert_in_delta 0.4, generation.refine_denoising_strength
    assert generation.enable_hires
    assert_equal "Latent", generation.hires_upscaler
    assert_in_delta 1.5, generation.hires_scale
  end

  test "default_for_kind returns default preset within kind" do
    assert_equal generation_presets(:chojugiga), GenerationPreset.default_for_kind("draft")
    assert_equal generation_presets(:chojugiga_refine), GenerationPreset.default_for_kind("refine")
  end

  test "refine preset fills base attributes without sd catalog fields" do
    preset = GenerationPreset.new(
      name: "Test Refine",
      preset_kind: "refine",
      refine_denoising_strength: 0.35,
      enable_hires: true,
      hires_upscaler: "Latent",
      hires_scale: 1.5,
      hires_denoising_strength: 0.35,
      refine_steps: 35
    )

    assert preset.valid?
    assert_equal "refine", preset.sd_model
    assert_equal "[]", preset.loras
    assert_equal "euler_a", preset.sampler_name
  end

  test "only one default preset per kind" do
    first = GenerationPreset.create!(
      name: "Draft A",
      preset_kind: "draft",
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
      name: "Draft B",
      preset_kind: "draft",
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

    refine_first = GenerationPreset.create!(
      name: "Refine A",
      preset_kind: "refine",
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
    refine_second = GenerationPreset.create!(
      name: "Refine B",
      preset_kind: "refine",
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

    assert_not refine_first.reload.default?
    assert refine_second.reload.default?
    assert second.reload.default?
  end
end
