# frozen_string_literal: true

require "test_helper"

class OpenAiStreamingFinishReasonTest < ActiveSupport::TestCase
  setup do
    @provider = RubyLLM::Providers::OpenAI.new(RubyLLM.config)
    Nyoy::FinishReasonCapture.reset!
  end

  teardown do
    Nyoy::FinishReasonCapture.reset!
  end

  test "attaches finish_reason length from openai stream payload" do
    chunk = @provider.send(
      :build_chunk,
      {
        "model" => "qwen",
        "choices" => [
          {
            "delta" => {},
            "finish_reason" => "length"
          }
        ]
      }
    )

    assert_equal "length", chunk.finish_reason
    assert Nyoy::FinishReasonCapture.length?
  end

  test "omits finish_reason when absent" do
    chunk = @provider.send(
      :build_chunk,
      {
        "model" => "qwen",
        "choices" => [
          {
            "delta" => { "content" => "hi" }
          }
        ]
      }
    )

    refute chunk.respond_to?(:finish_reason) && chunk.finish_reason.present?
    refute Nyoy::FinishReasonCapture.length?
  end
end
