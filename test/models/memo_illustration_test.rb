# frozen_string_literal: true

require "test_helper"

class MemoIllustrationTest < ActiveSupport::TestCase
  test "requires body" do
    illustration = MemoIllustration.new
    assert_not illustration.valid?
    assert_includes illustration.errors[:body], "can't be blank"
  end

  test "valid without skill or sd_model at creation (style flow)" do
    illustration = MemoIllustration.new(body: "メモ", style_id: "chojugiga_emaki")
    assert illustration.valid?
  end

  test "resolved_negative_prompt prefers snapshot column" do
    illustration = MemoIllustration.new(
      body: "メモ",
      resolved_negative_prompt: "photorealistic, 3d"
    )
    assert_equal "photorealistic, 3d", illustration.resolved_negative_prompt
  end

  test "style_label resolves from style_id" do
    illustration = MemoIllustration.new(body: "メモ", style_id: prompt_styles(:chojugiga).style_id)
    assert_equal prompt_styles(:chojugiga).name, illustration.style_label
  end

  test "loras_for_api normalizes resolved_loras" do
    illustration = MemoIllustration.new(
      body: "メモ",
      resolved_loras: [{ "path" => "a.safetensors", "multiplier" => 0.8 }, { "multiplier" => 1.0 }]
    )
    entries = illustration.loras_for_api
    assert_equal 1, entries.size
    assert_equal "a.safetensors", entries.first["path"]
    assert_in_delta 0.8, entries.first["multiplier"], 0.001
  end

  test "build_inpaint_prompt assembles prefix delta and suffix" do
    illustration = MemoIllustration.new(
      body: "メモ",
      style_id: prompt_styles(:chojugiga).style_id
    )
    style = illustration.prompt_style

    prompt = illustration.build_inpaint_prompt(
      delta: "natural hands",
      include_prefix: true,
      include_suffix: true
    )

    assert_equal [style.prompt_prefix, "natural hands", style.prompt_suffix].join(", "), prompt
  end

  test "build_inpaint_prompt requires content" do
    illustration = MemoIllustration.new(body: "メモ", style_id: prompt_styles(:chojugiga).style_id)

    assert_raises(RuntimeError) do
      illustration.build_inpaint_prompt(delta: "", include_prefix: false, include_suffix: false)
    end
  end

  test "inpaintable when completed with image" do
    illustration = MemoIllustration.new(body: "メモ", status: "completed")
    illustration.image.attach(io: StringIO.new("png"), filename: "a.png", content_type: "image/png")
    assert illustration.inpaintable?
  end

  test "not inpaintable while generating" do
    illustration = MemoIllustration.new(body: "メモ", status: "generating")
    illustration.image.attach(io: StringIO.new("png"), filename: "a.png", content_type: "image/png")
    assert_not illustration.inpaintable?
  end

  test "inpaint_job_runnable when inpainting after submit" do
    illustration = MemoIllustration.new(body: "メモ", status: "inpainting")
    illustration.image.attach(io: StringIO.new("png"), filename: "a.png", content_type: "image/png")

    assert_not illustration.inpaintable?
    assert illustration.inpaint_job_runnable?
  end

  test "recover_stale_inpaint resets old inpainting status" do
    illustration = MemoIllustration.create!(
      body: "メモ",
      status: "inpainting",
      image_started_at: 5.minutes.ago
    )
    illustration.image.attach(io: StringIO.new("png"), filename: "a.png", content_type: "image/png")

    illustration.recover_stale_inpaint!

    assert_equal "failed", illustration.status
    assert illustration.inpaintable?
  end

  test "inpaint_prompt_breakdown_for exposes prefix delta and suffix separately" do
    illustration = MemoIllustration.new(body: "メモ", style_id: prompt_styles(:chojugiga).style_id)
    style = illustration.prompt_style
    attachment = Struct.new(:metadata).new(
      {
        "inpaint_include_prefix" => true,
        "inpaint_include_suffix" => true,
        "inpaint_note_translated" => "holding a rose",
        "inpaint_prompt" => [style.prompt_prefix, "holding a rose", style.prompt_suffix].join(", ")
      }
    )

    breakdown = illustration.inpaint_prompt_breakdown_for(attachment)

    assert_equal style.prompt_prefix, breakdown[:prefix]
    assert_equal "holding a rose", breakdown[:delta]
    assert_equal style.prompt_suffix, breakdown[:suffix]
  end
end
