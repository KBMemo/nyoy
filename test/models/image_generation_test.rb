# frozen_string_literal: true

require "test_helper"

class ImageGenerationTest < ActiveSupport::TestCase
  test "requires sd model and at least one prompt source" do
    generation = ImageGeneration.new(loras: "[]")
    assert_not generation.valid?
    assert_includes generation.errors[:sd_model], "can't be blank"
    assert_includes generation.errors[:base], "日本語プロンプトまたは SD プロンプトを入力してください"
  end

  test "accepts japanese prompt only for style flow without sd model" do
    generation = ImageGeneration.new(japanese_prompt: "テスト")
    assert generation.valid?
  end

  test "direct flow requires sd model profile and accepts japanese only" do
    generation = ImageGeneration.new(
      generation_flow: "direct",
      japanese_prompt: "テスト",
      sd_model_profile: sd_model_profiles(:pony),
      loras: "[]"
    )
    assert generation.valid?
    assert generation.direct_flow?
  end

  test "direct flow rejects missing sd model profile" do
    generation = ImageGeneration.new(
      generation_flow: "direct",
      japanese_prompt: "テスト",
      loras: "[]"
    )
    assert_not generation.valid?
    assert generation.errors.key?(:sd_model_profile)
  end

  test "direct krea2 flow accepts cfg scale zero" do
    generation = ImageGeneration.new(
      generation_flow: "direct",
      japanese_prompt: "テスト",
      sd_model_profile: sd_model_profiles(:krea2),
      cfg_scale: 0,
      loras: "[]"
    )
    assert generation.valid?
  end

  test "direct krea2 flow rejects negative cfg scale" do
    generation = ImageGeneration.new(
      generation_flow: "direct",
      japanese_prompt: "テスト",
      sd_model_profile: sd_model_profiles(:krea2),
      cfg_scale: -0.5,
      loras: "[]"
    )
    assert_not generation.valid?
    assert generation.errors.key?(:cfg_scale)
  end

  test "direct pony flow rejects cfg scale zero" do
    generation = ImageGeneration.new(
      generation_flow: "direct",
      japanese_prompt: "テスト",
      sd_model_profile: sd_model_profiles(:pony),
      cfg_scale: 0,
      loras: "[]"
    )
    assert_not generation.valid?
    assert generation.errors.key?(:cfg_scale)
  end

  test "accepts sd prompt only with sd model for legacy flow" do
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

  test "refineable when awaiting selection or after completion" do
    generation = ImageGeneration.create!(
      prompt: "test",
      sd_model: "flat2d",
      loras: "[]",
      status: "awaiting_selection"
    )
    generation.drafts.attach(
      io: StringIO.new("x"),
      filename: "d.png",
      content_type: "image/png"
    )
    assert generation.refineable?

    generation.update!(status: "completed")
    assert generation.refineable?

    generation.update!(status: "refining")
    assert_not generation.refineable?
  end

  test "refined_image_label includes draft index" do
    generation = ImageGeneration.create!(
      prompt: "test",
      sd_model: "flat2d",
      loras: "[]"
    )
    generation.refined_images.attach(
      io: StringIO.new("x"),
      filename: "refined.png",
      content_type: "image/png",
      metadata: { draft_index: 2, sequence: 3 }
    )

    assert_equal "仕上がり 3 · ラフ案 3", generation.refined_image_label(generation.refined_images.attachments.first)
  end

  test "resolved_negative_prompt prefers snapshot column" do
    generation = ImageGeneration.new(
      japanese_prompt: "テスト",
      resolved_negative_prompt: "photorealistic"
    )
    assert_equal "photorealistic", generation.resolved_negative_prompt
  end

  test "style_label resolves from style_id" do
    generation = ImageGeneration.new(japanese_prompt: "x", style_id: prompt_styles(:chojugiga).style_id)
    assert_equal prompt_styles(:chojugiga).name, generation.style_label
  end

  test "loras_for_api uses resolved_loras when present" do
    generation = ImageGeneration.new(
      japanese_prompt: "x",
      resolved_loras: [{ "path" => "a.safetensors", "multiplier" => 0.8 }]
    )
    assert_equal 1, generation.loras_for_api.size
  end

  test "hires target dimensions scale from base size" do
    generation = ImageGeneration.new(width: 512, height: 768, hires_scale: 1.5, loras: "[]")
    assert_equal 768, generation.hires_target_width
    assert_equal 1152, generation.hires_target_height
  end

  test "draft dimensions scale to about two thirds aligned to 8px" do
    generation = ImageGeneration.new(width: 768, height: 768, loras: "[]")
    assert_equal 512, generation.draft_width
    assert_equal 512, generation.draft_height
    assert generation.needs_output_upscale?

    generation.width = 1024
    generation.height = 768
    assert_equal 680, generation.draft_width
    assert_equal 512, generation.draft_height
    assert generation.needs_output_upscale?
  end
end
