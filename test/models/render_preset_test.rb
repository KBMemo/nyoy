# frozen_string_literal: true

require "test_helper"

class RenderPresetTest < ActiveSupport::TestCase
  test "valid fixtures" do
    assert render_presets(:single).valid?
    assert render_presets(:draft).valid?
    assert render_presets(:refine).valid?
  end

  test "requires name and valid kind" do
    preset = RenderPreset.new(kind: "bogus")
    assert_not preset.valid?
    assert preset.errors.key?(:name)
    assert preset.errors.key?(:kind)
  end

  test "kind predicate methods" do
    assert render_presets(:single).single?
    assert render_presets(:draft).draft?
    assert render_presets(:refine).refine?
  end

  test "default_for_kind returns the kind default" do
    assert_equal render_presets(:single), RenderPreset.default_for_kind("single")
    assert_equal render_presets(:refine), RenderPreset.default_for_kind("refine")
  end

  test "setting default clears other defaults within the same kind" do
    other = RenderPreset.create!(name: "案出し（予備）", kind: "draft", draft_batch_size: 2, default: true)

    assert_equal false, render_presets(:draft).reload.default
    assert other.reload.default
    # other kinds untouched
    assert render_presets(:single).reload.default
  end

  test "hires_upscaler must be allowed when present" do
    preset = render_presets(:refine)
    preset.hires_upscaler = "Bogus"
    assert_not preset.valid?
    assert preset.errors.key?(:hires_upscaler)
  end
end
