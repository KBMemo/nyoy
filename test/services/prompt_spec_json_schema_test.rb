# frozen_string_literal: true

require "test_helper"

class PromptSpecJsonSchemaTest < ActiveSupport::TestCase
  test "builds llama.cpp compatible json schema payload" do
    schema = PromptSpecJsonSchema.build(
      allowed_loras: ["ChojuGiga_Illustrious"],
      allowed_samplers: ["euler_a"],
      allowed_models: ["pony-v6"]
    )

    assert_equal "json_schema", schema[:type]
    assert_equal "prompt_spec", schema[:json_schema][:name]
    assert_includes schema[:json_schema][:schema][:required], "positive_prompt"
  end
end
