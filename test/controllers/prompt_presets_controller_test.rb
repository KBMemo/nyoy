# frozen_string_literal: true

require "test_helper"

class PromptPresetsControllerTest < ActionDispatch::IntegrationTest
  test "save_as creates duplicate preset with numbered suffix" do
    preset = prompt_presets(:chojugiga)

    assert_difference -> { PromptPreset.count }, 1 do
      patch prompt_preset_path(preset), params: {
        save_as: "別名で保存",
        prompt_preset: {
          name: preset.name,
          model_family: preset.model_family,
          positive_template: "branch positive",
          negative_template: preset.negative_template,
          default_params_json: preset.default_params_json
        }
      }
    end

    duplicate = PromptPreset.order(:id).last
    assert_redirected_to prompt_preset_path(duplicate)
    assert_equal "鳥獣戯画テンプレ（１）", duplicate.name
    assert_equal "branch positive", duplicate.positive_template
    assert_equal preset.name, preset.reload.name
  end
end
