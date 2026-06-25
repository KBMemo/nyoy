# frozen_string_literal: true

require "test_helper"

class ImageGenerationTest < ActiveSupport::TestCase
  test "requires sd model and at least one prompt source" do
    generation = ImageGeneration.new(loras: "[]")
    assert_not generation.valid?
    assert_includes generation.errors[:sd_model], "can't be blank"
    assert_includes generation.errors[:base], "日本語プロンプトまたは SD プロンプトを入力してください"
  end

  test "accepts japanese prompt only" do
    generation = ImageGeneration.new(
      japanese_prompt: "テスト",
      sd_model: "flat2d",
      loras: "[]"
    )
    assert generation.valid?
  end

  test "accepts sd prompt only" do
    generation = ImageGeneration.new(
      prompt: "chojugiga, rabbit, frog",
      sd_model: "flat2d",
      loras: "[]"
    )
    assert generation.valid?
  end

  test "defaults status to pending" do
    generation = ImageGeneration.new(
      japanese_prompt: "テスト",
      sd_model: "flat2d",
      loras: "[]"
    )
    assert_equal "pending", generation.status
    assert_equal "euler_a", generation.sampler_name
  end

  test "copies all settings to another generation" do
    source = ImageGeneration.new(
      japanese_prompt: "鳥獣戯画",
      prompt: "chojugiga, rabbit and frog",
      negative_prompt: "low quality",
      sd_model: "pony-v6",
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      seed: 42,
      sampler_name: "euler_a",
      vae_tiling: true,
      loras: '[{"name":"ChojuGiga_Illustrious","path":"chojugiga/ChojuGiga_Illustrious.safetensors","multiplier":0.8}]'
    )

    copy = ImageGeneration.new
    source.apply_settings_to(copy)

    assert_equal "鳥獣戯画", copy.japanese_prompt
    assert_equal "chojugiga, rabbit and frog", copy.prompt
    assert_equal "pony-v6", copy.sd_model
    assert_equal 768, copy.width
    assert_equal 0.8, copy.loras_array.first["multiplier"]
  end

  test "display_summary prefers japanese prompt" do
    generation = ImageGeneration.new(japanese_prompt: "日本語", prompt: "english")
    assert_equal "日本語", generation.display_summary
  end

  test "draft_steps_for_api falls back to capped steps" do
    generation = ImageGeneration.new(steps: 30, loras: "[]")
    assert_equal 18, generation.draft_steps_for_api

    generation.draft_steps = 12
    assert_equal 12, generation.draft_steps_for_api
  end

  test "refine_steps_for_api falls back to steps" do
    generation = ImageGeneration.new(steps: 28, loras: "[]")
    assert_equal 28, generation.refine_steps_for_api

    generation.refine_steps = 40
    assert_equal 40, generation.refine_steps_for_api
  end

  test "awaiting_selection is not in progress or finished" do
    generation = ImageGeneration.new(status: "awaiting_selection", loras: "[]")
    assert generation.awaiting_selection?
    assert_not generation.in_progress?
    assert_not generation.finished?
  end
end
