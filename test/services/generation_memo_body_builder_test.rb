# frozen_string_literal: true

require "test_helper"

class GenerationMemoBodyBuilderTest < ActiveSupport::TestCase
  test "builds markdown body for image generation" do
    generation = ImageGeneration.new(
      japanese_prompt: "夕暮れの猫",
      prompt: "cat at sunset",
      resolved_negative_prompt: "low quality",
      sd_model: "test.safetensors",
      style_id: "chojugiga_emaki",
      width: 768,
      height: 512,
      steps: 22,
      draft_batch_size: 4,
      draft_steps: 18,
      refine_steps: 22,
      refine_denoising_strength: 0.4,
      enable_hires: true,
      cfg_scale: 6.0,
      seed: 123,
      sampler_name: "euler_a",
      loras: "[]",
      status: "completed"
    )
    generation.define_singleton_method(:style_label) { "鳥獣戯画" }

    generation.save!

    body = GenerationMemoBodyBuilder.build(source: generation, attachment: nil)

    assert_includes body, "## 日本語プロンプト"
    assert_includes body, "夕暮れの猫"
    assert_includes body, "cat at sunset"
    assert_includes body, "low quality"
    assert_includes body, "- モデル: test.safetensors"
    assert_includes body, "/image_generations/#{generation.id}"
    assert_includes body, "テキスト生成（如意）"
  end

  test "format_model prefers sd_model_profile name for direct flow" do
    profile = sd_model_profiles(:pony)
    generation = ImageGeneration.create!(
      generation_flow: "direct",
      prompt: "test",
      sd_model_profile: profile,
      sd_model: profile.key,
      loras: "[]",
      status: "completed"
    )

    body = GenerationMemoBodyBuilder.build(source: generation, attachment: nil)

    assert_includes body, "- モデル: Pony Diffusion V6 XL"
  end

  test "title_for truncates long prompts" do
    generation = ImageGeneration.new(japanese_prompt: "あ" * 80)

    assert_equal "#{'あ' * 57}...", GenerationMemoBodyBuilder.title_for(source: generation)
  end

  test "tags include generation kind" do
    generation = ImageGeneration.new

    assert_equal %w[nyoy ai-image image-generation], GenerationMemoBodyBuilder.tags_for(generation)
  end
end
