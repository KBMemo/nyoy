# frozen_string_literal: true

require "test_helper"

class SdPromptTokensControllerTest < ActionDispatch::IntegrationTest
  test "returns token count as json" do
    post sd_prompt_token_count_path, params: { text: "a photo of a cat" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal 5, body["count"]
    assert_equal "5 / 75", body["label"]
    assert_equal 75, body["limit"]
    assert_equal false, body["over_limit"]
  end
end
