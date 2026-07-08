# frozen_string_literal: true

require "test_helper"

class SdModelProfileTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert sd_model_profiles(:pony).valid?
  end

  test "requires key, name, family, switch_key" do
    profile = SdModelProfile.new
    assert_not profile.valid?
    assert profile.errors.key?(:key)
    assert profile.errors.key?(:name)
    assert profile.errors.key?(:family)
    assert profile.errors.key?(:switch_key)
  end

  test "key is unique" do
    profile = SdModelProfile.new(
      key: sd_model_profiles(:pony).key,
      name: "dup",
      family: "pony",
      switch_key: "dup"
    )
    assert_not profile.valid?
    assert profile.errors.key?(:key)
  end

  test "family must be in allowed list" do
    profile = sd_model_profiles(:pony)
    profile.family = "unknown"
    assert_not profile.valid?
    assert profile.errors.key?(:family)
  end

  test "sd35 is an allowed family" do
    profile = sd_model_profiles(:pony)
    profile.family = "sd35"
    assert profile.valid?
    assert_equal "SD 3.5", profile.family_label
  end

  test "resolved_default_params falls back to family defaults" do
    profile = SdModelProfile.new(family: "sd35", default_params: {})
    assert_equal SdModelProfile::FAMILY_DEFAULT_PARAMS["sd35"], profile.resolved_default_params
  end

  test "resolved_default_params lets profile override family baseline" do
    profile = SdModelProfile.new(family: "sd35", default_params: { "steps" => 40 })
    resolved = profile.resolved_default_params
    assert_equal 40, resolved["steps"]
    assert_equal 1024, resolved["width"]
  end

  test "default_params_json round trips" do
    profile = SdModelProfile.new
    profile.default_params_json = '{"steps":20}'
    assert_equal({ "steps" => 20 }, profile.default_params)
  end

  test "enabled and ordered scopes" do
    assert_includes SdModelProfile.enabled.ordered, sd_model_profiles(:pony)
  end

  test "linked_to_styles reflects prompt style models" do
    assert sd_model_profiles(:illustrious).linked_to_styles?
    assert_not SdModelProfile.create!(
      key: "solo-model",
      name: "Solo",
      family: "sd15",
      switch_key: "solo-model"
    ).linked_to_styles?
  end
end
