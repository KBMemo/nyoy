# frozen_string_literal: true

require "test_helper"

class PromptStylesControllerTest < ActionDispatch::IntegrationTest
  test "index lists styles" do
    get prompt_styles_path

    assert_response :success
    assert_match prompt_styles(:chojugiga).name, response.body
  end

  test "show displays style" do
    style = prompt_styles(:chojugiga)

    get prompt_style_path(style)

    assert_response :success
    assert_match style.style_id, response.body
    assert_match style.prompt_prefix, response.body
  end

  test "create style with models" do
    illustrious = sd_model_profiles(:illustrious)

    assert_difference -> { PromptStyle.count }, 1 do
      post prompt_styles_path, params: {
        prompt_style: {
          style_id: "test_style",
          name: "Test Style",
          prompt_prefix: "test prefix",
          generation_defaults_json: '{"steps":20}',
          aspect_presets_json: '{"square":{"width":512,"height":512}}',
          enabled: true,
          sort_order: 99,
          model_profile_ids: [illustrious.id],
          default_model_profile_id: illustrious.id
        }
      }
    end

    style = PromptStyle.find_by!(style_id: "test_style")
    assert_redirected_to prompt_style_path(style)
    assert_equal illustrious, style.default_model
    assert_equal({ "steps" => 20 }, style.generation_defaults)
  end

  test "update style" do
    style = prompt_styles(:chojugiga)

    patch prompt_style_path(style), params: {
      prompt_style: {
        name: "#{style.name} (updated)",
        model_profile_ids: style.prompt_style_models.map(&:sd_model_profile_id),
        default_model_profile_id: style.default_style_model.sd_model_profile_id
      }
    }

    assert_redirected_to prompt_style_path(style)
    assert_match "updated", style.reload.name
  end

  test "update ignores style_id when referenced" do
    style = prompt_styles(:chojugiga)
    MemoIllustration.create!(body: "test", style_id: style.style_id, status: "completed")

    patch prompt_style_path(style), params: {
      prompt_style: {
        style_id: "hacked-style",
        name: style.name,
        model_profile_ids: style.prompt_style_models.map(&:sd_model_profile_id),
        default_model_profile_id: style.default_style_model.sd_model_profile_id
      }
    }

    assert_redirected_to prompt_style_path(style)
    assert_equal "chojugiga_emaki", style.reload.style_id
  end

  test "destroy blocked when referenced" do
    style = prompt_styles(:chojugiga)
    MemoIllustration.create!(body: "test", style_id: style.style_id, status: "completed")

    assert_no_difference -> { PromptStyle.count } do
      delete prompt_style_path(style)
    end

    assert_redirected_to prompt_style_path(style)
    follow_redirect!
    assert_match "削除できません", response.body
  end

  test "destroy unreferenced style" do
    style = PromptStyle.create!(
      style_id: "orphan-style",
      name: "Orphan",
      prompt_prefix: "orphan"
    )

    assert_difference -> { PromptStyle.count }, -1 do
      delete prompt_style_path(style)
    end

    assert_redirected_to prompt_styles_path
  end
end
