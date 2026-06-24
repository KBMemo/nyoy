# frozen_string_literal: true

require "test_helper"

class SdPromptTranslatorTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response, keyword_init: true) do
    def chat(messages:, temperature:, max_tokens:)
      response
    end

    def message_text(response)
      LlamaCppClient.message_text(response)
    end
  end

  test "uses content field from llama response" do
    client = FakeClient.new(
      response: {
        "choices" => [
          { "message" => { "content" => "blue hair, 1girl" } }
        ]
      }
    )

    result = SdPromptTranslator.new(client: client).translate("青い髪の少女")
    assert_equal "blue hair, 1girl", result
  end

  test "falls back to reasoning content when content is empty" do
    client = FakeClient.new(
      response: {
        "choices" => [
          {
            "message" => {
              "content" => "",
              "reasoning_content" => "* Translation\n\"masterpiece, blue hair, girl\""
            }
          }
        ]
      }
    )

    result = SdPromptTranslator.new(client: client).translate("青い髪の少女")
    assert_equal "masterpiece, blue hair, girl", result
  end
end
