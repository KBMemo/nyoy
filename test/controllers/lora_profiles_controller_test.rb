# frozen_string_literal: true

require "test_helper"

class LoraProfilesControllerTest < ActionDispatch::IntegrationTest
  test "index lists profiles" do
    get lora_profiles_path

    assert_response :success
    assert_match lora_profiles(:chojugiga).name, response.body
  end

  test "show displays profile" do
    profile = lora_profiles(:chojugiga)

    get lora_profile_path(profile)

    assert_response :success
    assert_match profile.key, response.body
    assert_match profile.path, response.body
  end

  test "create profile" do
    assert_difference -> { LoraProfile.count }, 1 do
      post lora_profiles_path, params: {
        lora_profile: {
          key: "test-lora",
          name: "Test LoRA",
          family: "illustrious",
          path: "test/Test.safetensors",
          trigger_words_text: "test, trigger",
          default_multiplier: 0.8,
          min_multiplier: 0.5,
          max_multiplier: 1.0,
          enabled: true
        }
      }
    end

    profile = LoraProfile.find_by!(key: "test-lora")
    assert_redirected_to lora_profile_path(profile)
    assert_equal %w[test trigger], profile.trigger_words_list
  end

  test "update profile" do
    profile = LoraProfile.create!(
      key: "orphan-lora",
      name: "Orphan",
      path: "orphan/Orphan.safetensors",
      default_multiplier: 0.7,
      min_multiplier: 0.0,
      max_multiplier: 1.5
    )

    patch lora_profile_path(profile), params: {
      lora_profile: { name: "Orphan (updated)", notes: "memo" }
    }

    assert_redirected_to lora_profile_path(profile)
    assert_equal "Orphan (updated)", profile.reload.name
  end

  test "update key when not linked to any style" do
    profile = LoraProfile.create!(
      key: "orphan-lora",
      name: "Orphan",
      path: "orphan/Orphan.safetensors",
      default_multiplier: 0.7,
      min_multiplier: 0.0,
      max_multiplier: 1.5
    )

    patch lora_profile_path(profile), params: {
      lora_profile: {
        key: "orphan-renamed",
        path: "orphan/Renamed.safetensors"
      }
    }

    assert_redirected_to lora_profile_path(profile)
    profile.reload
    assert_equal "orphan-renamed", profile.key
    assert_equal "orphan/Renamed.safetensors", profile.path
  end

  test "update ignores key change when linked to a style" do
    profile = lora_profiles(:chojugiga)
    original_key = profile.key

    patch lora_profile_path(profile), params: {
      lora_profile: {
        key: "hacked-key",
        name: "#{profile.name} (updated)"
      }
    }

    assert_redirected_to lora_profile_path(profile)
    profile.reload
    assert_equal original_key, profile.key
    assert_match "updated", profile.name
  end

  test "edit shows read-only key when linked to a style" do
    profile = lora_profiles(:chojugiga)

    get edit_lora_profile_path(profile)

    assert_response :success
    assert_match "スタイルに紐づいているため変更できません", response.body
    assert_no_match 'name="lora_profile[key]"', response.body
  end

  test "destroy blocked when linked to a style" do
    profile = lora_profiles(:chojugiga)

    assert_no_difference -> { LoraProfile.count } do
      delete lora_profile_path(profile)
    end

    assert_redirected_to lora_profile_path(profile)
    follow_redirect!
    assert_match "削除できません", response.body
  end

  test "destroy unlinked profile" do
    profile = LoraProfile.create!(
      key: "orphan-lora",
      name: "Orphan",
      path: "orphan/Orphan.safetensors",
      default_multiplier: 0.7,
      min_multiplier: 0.0,
      max_multiplier: 1.5
    )

    assert_difference -> { LoraProfile.count }, -1 do
      delete lora_profile_path(profile)
    end

    assert_redirected_to lora_profiles_path
  end
end
