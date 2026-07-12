# frozen_string_literal: true

require "test_helper"

class DirectPromptJsonSchemaTest < ActiveSupport::TestCase
  test "builds strict schema with prompt and negative_prompt" do
    schema = DirectPromptJsonSchema.build

    inner = schema[:json_schema][:schema]
    assert schema[:json_schema][:strict]
    assert_equal "direct_prompt", schema[:json_schema][:name]
    assert_equal %w[prompt negative_prompt], inner[:required]
    assert_equal false, inner[:additionalProperties]
    assert_equal "string", inner[:properties][:prompt][:type]
    assert_equal "string", inner[:properties][:negative_prompt][:type]
  end
end
