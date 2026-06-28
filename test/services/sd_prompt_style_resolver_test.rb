# frozen_string_literal: true

require "test_helper"

class SdPromptStyleResolverTest < ActiveSupport::TestCase
  def resolve(**overrides)
    SdPromptStyleResolver.new(**{
      style_id: "chojugiga_emaki",
      subject_prompt: "rabbit and frog wrestling"
    }.merge(overrides)).call
  end

  test "uses default model and builds prompt with prefix, subject, triggers, suffix" do
    result = resolve

    assert_equal "chojugiga_emaki", result[:style_id]
    assert_equal "pony-v6", result[:resolved_model_key]
    assert_equal "pony-v6", result[:switch_key]
    assert_includes result[:resolved_prompt], "chojugiga, emaki"
    assert_includes result[:resolved_prompt], "rabbit and frog wrestling"
    assert_includes result[:resolved_prompt], "chojugiga" # trigger words injected
    assert_includes result[:resolved_prompt], "ink brush strokes" # suffix
  end

  test "merges style negative with negative_extra and dedupes" do
    result = resolve(negative_extra: "photorealistic, busy background")

    tags = result[:resolved_negative_prompt].split(",").map(&:strip)
    assert_includes tags, "busy background"
    assert_equal tags.uniq, tags
  end

  test "resolves loras from style with path and multiplier" do
    result = resolve

    entry = result[:resolved_loras].first
    assert_equal "chojugiga/ChojuGiga_Illustrious.safetensors", entry["path"]
    assert_in_delta 0.8, entry["multiplier"], 0.001
  end

  test "aspect_ratio maps to style dimensions" do
    result = resolve(aspect_ratio: "landscape")

    assert_equal 1024, result[:resolved_params]["width"]
    assert_equal 768, result[:resolved_params]["height"]
  end

  test "model_key override selects an allowed style model" do
    result = resolve(model_key: "flat2d")

    assert_equal "flat2d", result[:resolved_model_key]
  end

  test "unknown model_key falls back to default" do
    result = resolve(model_key: "does-not-exist")

    assert_equal "pony-v6", result[:resolved_model_key]
  end

  test "safe_overrides clamps within allowed range" do
    result = resolve(overrides: { "steps" => 999 })

    assert_equal 32, result[:resolved_params]["steps"]
  end

  test "safe_overrides ignores keys not in allowed_overrides" do
    result = resolve(overrides: { "width" => 4096 })

    assert_equal 768, result[:resolved_params]["width"]
  end

  test "raises on unknown style_id" do
    assert_raises(SdPromptStyleResolver::Error) do
      SdPromptStyleResolver.new(style_id: "nope", subject_prompt: "x").call
    end
  end

  test "raises on blank subject_prompt" do
    assert_raises(SdPromptStyleResolver::Error) do
      SdPromptStyleResolver.new(style_id: "chojugiga_emaki", subject_prompt: " ").call
    end
  end

  test "payload carries prompt, negative_prompt and lora" do
    payload = resolve[:payload]

    assert payload.key?("prompt")
    assert payload.key?("negative_prompt")
    assert payload.key?("lora")
    assert_equal payload["prompt"], resolve[:resolved_prompt]
  end
end
