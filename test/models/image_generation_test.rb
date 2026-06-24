# frozen_string_literal: true

require "test_helper"

class ImageGenerationTest < ActiveSupport::TestCase
  test "requires japanese prompt and sd model" do
    generation = ImageGeneration.new
    assert_not generation.valid?
    assert_includes generation.errors[:japanese_prompt], "can't be blank"
    assert_includes generation.errors[:sd_model], "can't be blank"
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
    assert_equal "pony-v6", copy.sd_model
    assert_equal 768, copy.width
    assert_equal 0.8, copy.loras_array.first["multiplier"]
  end
end
