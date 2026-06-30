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

  test "repairs truncated style plan json cut mid negative_extra" do
    truncated = '{"style_id":"watercolor_human_silhouette","subject_prompt":"minimal human silhouette, pastel watercolor background","negative_extra":"photorealistic, 3d, anime, detailed face'

    parsed = LlamaJsonParser.repair_truncated(truncated)

    assert_equal "watercolor_human_silhouette", parsed["style_id"]
    assert_includes parsed["subject_prompt"], "minimal human silhouette"
    assert_includes parsed["negative_extra"], "photorealistic"
    assert_equal "square", parsed["aspect_ratio"]
  end
end
