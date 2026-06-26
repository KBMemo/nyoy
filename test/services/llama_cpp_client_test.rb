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
end
