# frozen_string_literal: true

require "test_helper"

class LlamaCppClientTest < ActiveSupport::TestCase
  test "extracts quoted text from reasoning content" do
    response = {
      "choices" => [
        {
          "message" => {
            "content" => "",
            "reasoning_content" => "Task: translate\n\"1girl, blue hair, sakura\""
          }
        }
      ]
    }

    assert_equal "1girl, blue hair, sakura", LlamaCppClient.message_text(response)
  end

  test "prefers json object from reasoning content" do
    response = {
      "choices" => [
        {
          "message" => {
            "content" => "",
            "reasoning_content" => <<~REASONING
              ```json
              {"positive":"1girl","negative":"blurry"}
              ```
            REASONING
          }
        }
      ]
    }

    assert_equal '{"positive":"1girl","negative":"blurry"}', LlamaCppClient.message_text(response)
  end

  test "prefers parseable json in reasoning over truncated content" do
    response = {
      "choices" => [
        {
          "message" => {
            "content" => '{"style_id":"watercolor_human_silhouette","subject_prompt":"silhouette","negative_extra":"photorealistic, 3d, anime, detailed face',
            "reasoning_content" => '{"style_id":"watercolor_human_silhouette","subject_prompt":"silhouette","negative_extra":"photorealistic, 3d","aspect_ratio":"square"}'
          }
        }
      ]
    }

    parsed = JSON.parse(LlamaCppClient.message_text(response))

    assert_equal "square", parsed["aspect_ratio"]
    assert_equal "photorealistic, 3d", parsed["negative_extra"]
  end

  test "extracts text from array content" do
    response = {
      "choices" => [
        {
          "message" => {
            "content" => [
              { "type" => "text", "text" => "猫が写っています" }
            ]
          }
        }
      ]
    }

    assert_equal "猫が写っています", LlamaCppClient.message_text(response)
  end
end
