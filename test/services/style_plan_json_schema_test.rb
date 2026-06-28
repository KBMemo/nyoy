# frozen_string_literal: true

require "test_helper"

class StylePlanJsonSchemaTest < ActiveSupport::TestCase
  test "builds strict schema with style_id enum and required keys" do
    schema = StylePlanJsonSchema.build(style_ids: %w[chojugiga_emaki pencil_still_life_sketch])

    inner = schema[:json_schema][:schema]
    assert schema[:json_schema][:strict]
    assert_equal %w[chojugiga_emaki pencil_still_life_sketch], inner[:properties][:style_id][:enum]
    assert_equal StylePlanJsonSchema::ASPECT_RATIOS, inner[:properties][:aspect_ratio][:enum]
    assert_equal %w[style_id subject_prompt negative_extra aspect_ratio], inner[:required]
    assert_equal false, inner[:additionalProperties]
  end

  test "falls back to plain string when no style ids" do
    schema = StylePlanJsonSchema.build(style_ids: [])

    refute schema[:json_schema][:schema][:properties][:style_id].key?(:enum)
  end
end
