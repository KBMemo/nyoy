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
end
