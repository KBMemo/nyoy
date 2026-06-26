# frozen_string_literal: true

require "test_helper"

class PromptPresetTest < ActiveSupport::TestCase
  test "unique_copy_name appends full-width numbered suffix when name taken" do
    existing = prompt_presets(:chojugiga)

    assert_equal "鳥獣戯画テンプレ（１）", PromptPreset.unique_copy_name(existing.name)
  end

  test "unique_copy_name increments suffix until free" do
    existing = prompt_presets(:chojugiga)
    PromptPreset.create!(
      name: "鳥獣戯画テンプレ（１）",
      model_family: "pony",
      default_params: {}
    )

    assert_equal "鳥獣戯画テンプレ（２）", PromptPreset.unique_copy_name(existing.name)
  end

  test "duplicate_with copies attributes under a unique name" do
    source = prompt_presets(:chojugiga)
    duplicate = source.duplicate_with(
      name: source.name,
      model_family: source.model_family,
      positive_template: "updated positive",
      negative_template: source.negative_template,
      default_params_json: source.default_params_json
    )

    assert duplicate.save
    assert_equal "鳥獣戯画テンプレ（１）", duplicate.name
    assert_equal "updated positive", duplicate.positive_template
    assert_not_equal source.id, duplicate.id
  end
end
