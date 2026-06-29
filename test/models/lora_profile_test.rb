# frozen_string_literal: true

require "test_helper"

class LoraProfileTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert lora_profiles(:chojugiga).valid?
  end

  test "requires key, name, path" do
    profile = LoraProfile.new
    assert_not profile.valid?
    assert profile.errors.key?(:key)
    assert profile.errors.key?(:name)
    assert profile.errors.key?(:path)
  end

  test "key and path are unique" do
    existing = lora_profiles(:chojugiga)
    profile = LoraProfile.new(key: existing.key, name: "dup", path: existing.path)
    assert_not profile.valid?
    assert profile.errors.key?(:key)
    assert profile.errors.key?(:path)
  end

  test "multiplier range must be ordered" do
    profile = lora_profiles(:chojugiga)
    profile.min_multiplier = 1.0
    profile.max_multiplier = 0.5
    assert_not profile.valid?
    assert profile.errors.key?(:max_multiplier)
  end

  test "trigger_words_list setter splits and trims" do
    profile = LoraProfile.new
    profile.trigger_words_list = "chojugiga,  emaki , "
    assert_equal %w[chojugiga emaki], profile.trigger_words_list
  end

  test "trigger_words_list reads native array" do
    assert_equal %w[chojugiga emaki], lora_profiles(:chojugiga).trigger_words_list
  end

  test "linked_to_styles reflects prompt style loras" do
    assert lora_profiles(:chojugiga).linked_to_styles?
    assert_not LoraProfile.create!(
      key: "solo-lora",
      name: "Solo",
      path: "solo/Solo.safetensors",
      default_multiplier: 0.7,
      min_multiplier: 0.0,
      max_multiplier: 1.5
    ).linked_to_styles?
  end

  test "trigger_words_text round trips" do
    profile = LoraProfile.new
    profile.trigger_words_text = "chojugiga, emaki"
    assert_equal %w[chojugiga emaki], profile.trigger_words_list
    assert_equal "chojugiga, emaki", profile.trigger_words_text
  end
end
