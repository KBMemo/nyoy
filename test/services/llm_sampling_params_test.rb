# frozen_string_literal: true

require "test_helper"

class LlmSamplingParamsTest < ActiveSupport::TestCase
  test "normalizes and clamps values" do
    params = LlmSamplingParams.from(
      "temperature" => "0.7",
      "top_p" => 0.8,
      "top_k" => 20,
      "min_p" => 0.0,
      "presence_penalty" => 0.8,
      "frequency_penalty" => 0.2,
      "repeat_penalty" => 1.08,
      "max_tokens" => 1024
    )

    assert_in_delta 0.7, params.temperature
    assert_in_delta 0.8, params.top_p
    assert_equal 20, params.top_k
    assert_in_delta 0.0, params.min_p
    assert_in_delta 0.8, params.presence_penalty
    assert_in_delta 0.2, params.frequency_penalty
    assert_in_delta 1.08, params.repeat_penalty
    assert_equal 1024, params.max_tokens
  end

  test "to_request_params omits temperature and max_tokens" do
    params = LlmSamplingParams.from("temperature" => 0.7, "top_p" => 0.8, "max_tokens" => 1024)

    assert_equal({ top_p: 0.8 }, params.to_request_params)
  end

  test "from_props maps llama server defaults" do
    params = LlmSamplingParams.from_props(
      "default_generation_settings" => {
        "params" => {
          "temperature" => 0.7,
          "top_p" => 0.8,
          "top_k" => 20,
          "n_predict" => 1024,
          "penalty_repeat" => 1.08
        }
      }
    )

    assert_in_delta 0.7, params.temperature
    assert_equal 1024, params.max_tokens
    assert_in_delta 1.08, params.repeat_penalty
  end
end
