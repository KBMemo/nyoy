# frozen_string_literal: true

require "test_helper"

class SdPromptTemplatesControllerTest < ActionDispatch::IntegrationTest
  test "index lists templates" do
    get sd_prompt_templates_path

    assert_response :success
    assert_match sd_prompt_templates(:pony_family).name, response.body
  end

  test "show displays template" do
    template = sd_prompt_templates(:pony_family)

    get sd_prompt_template_path(template)

    assert_response :success
    assert_match template.name, response.body
    assert_match template.body, response.body
  end

  test "create family template" do
    assert_difference -> { SdPromptTemplate.count }, 1 do
      post sd_prompt_templates_path, params: {
        sd_prompt_template: {
          name: "SDXL 向け",
          body: "Generate for SDXL.",
          family: "sdxl",
          sort_order: 10,
          enabled: true
        }
      }
    end

    template = SdPromptTemplate.find_by!(name: "SDXL 向け")
    assert_redirected_to sd_prompt_template_path(template)
    assert_equal "sdxl", template.family
  end

  test "create model-specific template" do
    profile = sd_model_profiles(:pony)

    assert_difference -> { SdPromptTemplate.count }, 1 do
      post sd_prompt_templates_path, params: {
        sd_prompt_template: {
          name: "Pony custom",
          body: "Custom pony guidance.",
          sd_model_profile_id: profile.id,
          sort_order: 0,
          enabled: true
        }
      }
    end

    template = SdPromptTemplate.find_by!(name: "Pony custom")
    assert_equal profile, template.sd_model_profile
  end

  test "create rejects family and model together" do
    assert_no_difference -> { SdPromptTemplate.count } do
      post sd_prompt_templates_path, params: {
        sd_prompt_template: {
          name: "Invalid",
          body: "body",
          family: "pony",
          sd_model_profile_id: sd_model_profiles(:pony).id
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "update template" do
    template = sd_prompt_templates(:global_default)

    patch sd_prompt_template_path(template), params: {
      sd_prompt_template: { name: "Global (updated)", notes: "memo" }
    }

    assert_redirected_to sd_prompt_template_path(template)
    template.reload
    assert_equal "Global (updated)", template.name
    assert_equal "memo", template.notes
  end

  test "destroy template" do
    template = SdPromptTemplate.create!(name: "Disposable", body: "body", sort_order: 0)

    assert_difference -> { SdPromptTemplate.count }, -1 do
      delete sd_prompt_template_path(template)
    end

    assert_redirected_to sd_prompt_templates_path
  end

  test "new pre-fills sd model profile from query param" do
    profile = sd_model_profiles(:pony)

    get new_sd_prompt_template_path(sd_model_profile_id: profile.id)

    assert_response :success
    assert_select "select[name='sd_prompt_template[sd_model_profile_id]']" do
      assert_select "option[selected][value='#{profile.id}']"
    end
  end

  test "settings nav includes prompt templates link" do
    get sd_prompt_templates_path

    assert_response :success
    assert_match "生成テンプレート", response.body
  end
end
