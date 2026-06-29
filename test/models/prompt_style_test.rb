# frozen_string_literal: true

require "test_helper"

class PromptStyleTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert prompt_styles(:chojugiga).valid?
  end

  test "requires style_id, name, prompt_prefix" do
    style = PromptStyle.new
    assert_not style.valid?
    assert style.errors.key?(:style_id)
    assert style.errors.key?(:name)
    assert style.errors.key?(:prompt_prefix)
  end

  test "style_id is unique" do
    style = PromptStyle.new(
      style_id: prompt_styles(:chojugiga).style_id,
      name: "dup",
      prompt_prefix: "x"
    )
    assert_not style.valid?
    assert style.errors.key?(:style_id)
  end

  test "default_model returns the default style model" do
    assert_equal sd_model_profiles(:illustrious), prompt_styles(:chojugiga).default_model
  end

  test "style_model_for falls back to default when key blank" do
    assert_equal sd_model_profiles(:illustrious),
      prompt_styles(:chojugiga).style_model_for(nil).sd_model_profile
  end

  test "style_model_for picks the matching model" do
    assert_equal sd_model_profiles(:pony),
      prompt_styles(:chojugiga).style_model_for("pony-v6").sd_model_profile
  end

  test "requires exactly one default model when models present" do
    style = prompt_styles(:chojugiga)
    style.prompt_style_models.each { |m| m.update_column(:default, false) }
    style.reload
    assert_not style.valid?
    assert_includes style.errors[:base].join, "既定モデル"
  end

  test "aspect_dimensions returns mapped size" do
    assert_equal({ "width" => 1024, "height" => 768 },
      prompt_styles(:chojugiga).aspect_dimensions("landscape"))
  end
end
