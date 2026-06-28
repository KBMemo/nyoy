# frozen_string_literal: true

require "test_helper"

class PromptStyleModelTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert prompt_style_models(:chojugiga_pony).valid?
  end

  test "model is unique within a style" do
    dup = PromptStyleModel.new(
      prompt_style: prompt_styles(:chojugiga),
      sd_model_profile: sd_model_profiles(:pony)
    )
    assert_not dup.valid?
    assert dup.errors.key?(:sd_model_profile_id)
  end

  test "setting default clears other defaults in the same style" do
    flat = prompt_style_models(:chojugiga_flat2d)
    flat.update!(default: true)

    assert prompt_style_models(:chojugiga_pony).reload.default == false
    assert flat.reload.default
  end
end
