# frozen_string_literal: true

require "test_helper"

class PromptSpecTest < ActiveSupport::TestCase
  test "validates allowed loras and samplers" do
    spec = PromptSpec.from_json(
      {
        "positive_prompt" => "masterpiece, chojugiga",
        "negative_prompt" => "blurry",
        "sampler" => "euler_a",
        "loras" => [{ "name" => "ChojuGiga_Illustrious", "weight" => 0.8 }]
      }
    )

    assert spec.validate!(
      allowed_loras: ["ChojuGiga_Illustrious"],
      allowed_samplers: ["euler_a"],
      allowed_models: ["pony-v6"]
    )
  end

  test "rejects unknown lora" do
    spec = PromptSpec.from_json(
      {
        "positive_prompt" => "test",
        "loras" => [{ "name" => "Unknown_LoRA", "weight" => 1.0 }]
      }
    )

    assert_raises(PromptSpec::ValidationError) do
      spec.validate!(allowed_loras: [], allowed_samplers: ["euler_a"], allowed_models: [])
    end
  end
end
