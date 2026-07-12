# frozen_string_literal: true

require "test_helper"

class SdPromptTemplateResolverTest < ActiveSupport::TestCase
  test "resolves family template when no model-specific template exists" do
    profile = sd_model_profiles(:pony)

    assert_equal sd_prompt_templates(:pony_family), SdPromptTemplateResolver.for(sd_model_profile: profile)
  end

  test "prefers model-specific template over family template" do
    profile = sd_model_profiles(:pony)
    model_template = SdPromptTemplate.create!(
      name: "Pony model override",
      body: "model body",
      sd_model_profile: profile,
      sort_order: 0
    )

    assert_equal model_template, SdPromptTemplateResolver.for(sd_model_profile: profile)
  end

  test "falls back to global template when family template missing" do
    profile = sd_model_profiles(:flat2d)

    assert_equal sd_prompt_templates(:global_default), SdPromptTemplateResolver.for(sd_model_profile: profile)
  end

  test "uses explicit template when provided" do
    profile = sd_model_profiles(:pony)
    global = sd_prompt_templates(:global_default)

    assert_equal global, SdPromptTemplateResolver.for(sd_model_profile: profile, sd_prompt_template: global)
  end

  test "raises when explicit template is disabled" do
    profile = sd_model_profiles(:pony)
    template = sd_prompt_templates(:global_default)
    template.update!(enabled: false)

    assert_raises(SdPromptTemplateResolver::Error, match: /disabled/) do
      SdPromptTemplateResolver.for(sd_model_profile: profile, sd_prompt_template: template)
    end
  end

  test "raises when sd_model_profile is missing" do
    assert_raises(SdPromptTemplateResolver::Error, match: /required/) do
      SdPromptTemplateResolver.for(sd_model_profile: nil)
    end
  end

  test "respects sort_order within same scope" do
    profile = sd_model_profiles(:pony)
    SdPromptTemplate.create!(
      name: "Later pony family",
      body: "second",
      family: "pony",
      sort_order: 5
    )
    first = sd_prompt_templates(:pony_family)

    assert_equal first, SdPromptTemplateResolver.for(sd_model_profile: profile)
  end
end
