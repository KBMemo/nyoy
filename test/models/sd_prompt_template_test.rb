# frozen_string_literal: true

require "test_helper"

class SdPromptTemplateTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert sd_prompt_templates(:pony_family).valid?
    assert sd_prompt_templates(:global_default).valid?
  end

  test "requires name and body" do
    template = SdPromptTemplate.new
    assert_not template.valid?
    assert template.errors.key?(:name)
    assert template.errors.key?(:body)
  end

  test "family must be known when present" do
    template = sd_prompt_templates(:pony_family)
    template.family = "unknown"
    assert_not template.valid?
    assert template.errors.key?(:family)
  end

  test "family and model profile are mutually exclusive" do
    template = SdPromptTemplate.new(
      name: "conflict",
      body: "body",
      family: "pony",
      sd_model_profile: sd_model_profiles(:pony)
    )
    assert_not template.valid?
    assert_includes template.errors[:base], "ファミリ既定とモデル専用は同時に指定できません"
  end

  test "scope labels" do
    assert_equal "ファミリ既定（Pony）", sd_prompt_templates(:pony_family).scope_label
    assert_equal "グローバル既定", sd_prompt_templates(:global_default).scope_label

    model_template = SdPromptTemplate.create!(
      name: "Pony model",
      body: "model body",
      sd_model_profile: sd_model_profiles(:pony)
    )
    assert_equal "モデル専用", model_template.scope_label
  end

  test "ordered scope sorts by sort_order then name" do
    SdPromptTemplate.create!(name: "Zeta", body: "b", sort_order: 1)
    SdPromptTemplate.create!(name: "Alpha", body: "b", sort_order: 1)

    names = SdPromptTemplate.ordered.pluck(:name)
    assert_equal "Alpha", names.find { |n| n == "Alpha" }
    assert names.index("Alpha") < names.index("Zeta")
  end

  test "destroying sd model profile destroys model-specific templates" do
    profile = SdModelProfile.create!(
      key: "temp-model",
      name: "Temp",
      family: "sd15",
      switch_key: "temp-model"
    )
    SdPromptTemplate.create!(name: "Temp template", body: "body", sd_model_profile: profile)

    assert_difference -> { SdPromptTemplate.count }, -1 do
      profile.destroy!
    end
  end
end
