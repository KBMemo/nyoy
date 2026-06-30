# frozen_string_literal: true

require "base64"
require "test_helper"

class Img2imgSourceTransferTest < ActiveSupport::TestCase
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  test "transfers memo illustration image and generation settings" do
    illustration = MemoIllustration.create!(
      body: "カフェのメモ",
      status: "completed",
      positive_prompt: "cafe scene, watercolor",
      resolved_negative_prompt: "photorealistic, 3d",
      style_id: prompt_styles(:chojugiga).style_id,
      seed: 42,
      steps: 24,
      cfg_scale: 6.5,
      width: 768,
      height: 512,
      sd_model: "illustrious_pencil-XL",
      resolved_params: { "sampler_name" => "euler_a", "switch_key" => "illustrious_pencil-XL" }
    )
    illustration.image.attach(io: StringIO.new(PNG), filename: "a.png", content_type: "image/png")

    result = Img2imgSourceTransfer.call(from_memo: illustration.id)

    assert_equal "生成結果（メモイラスト ##{illustration.id}）", result.label
    assert_equal "カフェのメモ", result.settings[:japanese_prompt]
    assert_equal "cafe scene, watercolor", result.settings[:prompt]
    assert_equal "photorealistic, 3d", result.settings[:negative_prompt]
    assert_equal 42, result.settings[:seed]
    assert_equal 24, result.settings[:steps]
    assert_in_delta 6.5, result.settings[:cfg_scale]
    assert_equal PNG, result.blob.download
  end

  test "transfers image generation refined output settings" do
    generation = ImageGeneration.create!(
      japanese_prompt: "ウサギ",
      prompt: "rabbit, sumo",
      resolved_negative_prompt: "low quality",
      status: "completed",
      sampler_name: "euler_a",
      loras: "[]",
      sd_model: "test",
      seed: 99,
      steps: 22,
      cfg_scale: 6.0,
      width: 768,
      height: 768,
      refine_denoising_strength: 0.45,
      refine_steps: 18
    )
    generation.refined_images.attach(io: StringIO.new(PNG), filename: "refined.png", content_type: "image/png")
    attachment = generation.refined_images.attachments.first

    result = Img2imgSourceTransfer.call(
      from_image_generation: generation.id,
      attachment: "refined_#{attachment.id}"
    )

    assert_includes result.label, "仕上がり"
    assert_equal "rabbit, sumo", result.settings[:prompt]
    assert_equal "low quality", result.settings[:negative_prompt]
    assert_equal 99, result.settings[:seed]
    assert_equal 18, result.settings[:steps]
    assert_in_delta 0.45, result.settings[:denoising_strength]
  end
end
