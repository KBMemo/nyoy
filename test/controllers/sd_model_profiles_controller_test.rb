# frozen_string_literal: true

require "test_helper"

class SdModelProfilesControllerTest < ActionDispatch::IntegrationTest
  test "index lists profiles" do
    get sd_model_profiles_path

    assert_response :success
    assert_match sd_model_profiles(:illustrious).name, response.body
  end

  test "show displays profile" do
    profile = sd_model_profiles(:illustrious)

    get sd_model_profile_path(profile)

    assert_response :success
    assert_match profile.key, response.body
  end

  test "create profile" do
    assert_difference -> { SdModelProfile.count }, 1 do
      post sd_model_profiles_path, params: {
        sd_model_profile: {
          key: "test-model",
          name: "Test Model",
          family: "sd15",
          switch_key: "test-model",
          default_params_json: '{"steps":20}',
          enabled: true,
          sort_order: 99
        }
      }
    end

    profile = SdModelProfile.find_by!(key: "test-model")
    assert_redirected_to sd_model_profile_path(profile)
    assert_equal({ "steps" => 20 }, profile.default_params)
  end

  test "update profile" do
    profile = sd_model_profiles(:pony)

    patch sd_model_profile_path(profile), params: {
      sd_model_profile: {
        name: "Pony Diffusion V6 XL (updated)",
        notes: "seed 由来"
      }
    }

    assert_redirected_to sd_model_profile_path(profile)
    assert_equal "Pony Diffusion V6 XL (updated)", profile.reload.name
  end

  test "update key when not linked to any style" do
    profile = SdModelProfile.create!(
      key: "orphan-model",
      name: "Orphan",
      family: "sd15",
      switch_key: "orphan-model"
    )

    patch sd_model_profile_path(profile), params: {
      sd_model_profile: {
        key: "orphan-renamed",
        switch_key: "orphan-renamed"
      }
    }

    assert_redirected_to sd_model_profile_path(profile)
    profile.reload
    assert_equal "orphan-renamed", profile.key
    assert_equal "orphan-renamed", profile.switch_key
  end

  test "update ignores key change when linked to a style" do
    profile = sd_model_profiles(:illustrious)
    original_key = profile.key

    patch sd_model_profile_path(profile), params: {
      sd_model_profile: {
        key: "hacked-key",
        name: "#{profile.name} (updated)"
      }
    }

    assert_redirected_to sd_model_profile_path(profile)
    profile.reload
    assert_equal original_key, profile.key
    assert_match "updated", profile.name
  end

  test "edit shows read-only key when linked to a style" do
    profile = sd_model_profiles(:illustrious)

    get edit_sd_model_profile_path(profile)

    assert_response :success
    assert_match "スタイルに紐づいているため変更できません", response.body
    assert_no_match 'name="sd_model_profile[key]"', response.body
  end

  test "edit shows editable key when not linked to any style" do
    profile = SdModelProfile.create!(
      key: "orphan-model",
      name: "Orphan",
      family: "sd15",
      switch_key: "orphan-model"
    )

    get edit_sd_model_profile_path(profile)

    assert_response :success
    assert_match 'name="sd_model_profile[key]"', response.body
    assert_match "まだスタイルに紐づいていない間だけ", response.body
  end

  test "destroy blocked when linked to a style" do
    profile = sd_model_profiles(:illustrious)

    assert_no_difference -> { SdModelProfile.count } do
      delete sd_model_profile_path(profile)
    end

    assert_redirected_to sd_model_profile_path(profile)
    follow_redirect!
    assert_match "削除できません", response.body
  end

  test "destroy unlinked profile" do
    profile = SdModelProfile.create!(
      key: "orphan-model",
      name: "Orphan",
      family: "sd15",
      switch_key: "orphan-model"
    )

    assert_difference -> { SdModelProfile.count }, -1 do
      delete sd_model_profile_path(profile)
    end

    assert_redirected_to sd_model_profiles_path
  end
end
