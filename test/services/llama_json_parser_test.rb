# frozen_string_literal: true

require "test_helper"

class LlamaJsonParserTest < ActiveSupport::TestCase
  test "extracts json object from markdown fence" do
    text = <<~TEXT
      ```json
      {"positive":"1girl","negative":"blurry"}
      ```
    TEXT

    assert_equal '{"positive":"1girl","negative":"blurry"}', LlamaJsonParser.normalize(text)
  end

  test "extracts first balanced json object after preamble" do
    text = <<~TEXT
      Here is the plan:
      {"positive":"sunset","negative":"low quality","width":512}
    TEXT

    parsed = LlamaJsonParser.parse(text)

    assert_equal "sunset", parsed["positive"]
    assert_equal 512, parsed["width"]
  end
end
