# frozen_string_literal: true

require "test_helper"

class SdPromptPlannerTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response, keyword_init: true) do
    def chat(messages:, temperature:, max_tokens:)
      response
    end
  end

  test "parses json block with prompts and parameters" do
    client = FakeClient.new(
      response: {
        "choices" => [
          {
            "message" => {
              "content" => <<~CONTENT
                ```json
                {
                  "positive": "masterpiece, best quality, 1girl, cafe",
                  "negative": "worst quality, low quality",
                  "width": 768,
                  "height": 512,
                  "steps": 24,
                  "cfg_scale": 8.5,
                  "seed": 42
                }
                ```
              CONTENT
            }
          }
        ]
      }
    )

    skill = PromptSkill.new(body: "system")
    plan = SdPromptPlanner.new(client: client).plan(body: "カフェの女の子", skill: skill)

    assert_equal "masterpiece, best quality, 1girl, cafe", plan[:positive]
    assert_equal "worst quality, low quality", plan[:negative]
    assert_equal 768, plan[:width]
    assert_equal 512, plan[:height]
    assert_equal 24, plan[:steps]
    assert_equal 8.5, plan[:cfg_scale]
    assert_equal 42, plan[:seed]
  end

  test "parses json after conversational preamble" do
    client = FakeClient.new(
      response: {
        "choices" => [
          {
            "message" => {
              "content" => <<~CONTENT
                Here is the JSON:
                ```json
                {
                  "positive": "masterpiece, best quality, sunset",
                  "negative": "worst quality"
                }
                ```
              CONTENT
            }
          }
        ]
      }
    )

    skill = PromptSkill.new(body: "system")
    plan = SdPromptPlanner.new(client: client).plan(body: "夕焼け", skill: skill)

    assert_equal "masterpiece, best quality, sunset", plan[:positive]
    assert_equal "worst quality", plan[:negative]
  end

  test "parses bare json object without fences" do
    client = FakeClient.new(
      response: {
        "choices" => [
          {
            "message" => {
              "content" => "{\"positive\":\"1girl\",\"negative\":\"low quality\"}"
            }
          }
        ]
      }
    )

    skill = PromptSkill.new(body: "system")
    plan = SdPromptPlanner.new(client: client).plan(body: "test", skill: skill)

    assert_equal "1girl", plan[:positive]
  end
end
