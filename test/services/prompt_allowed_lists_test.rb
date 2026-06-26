# frozen_string_literal: true

require "test_helper"

class PromptAllowedListsTest < ActiveSupport::TestCase
  test "merges catalog loras with dictionary entries" do
    generation = ImageGeneration.new(sd_model: "pony-v6", loras: "[]")
    lists = PromptAllowedLists.new(
      generation: generation,
      lora_catalog: Class.new do
        def list
          [{ "name" => "Remote_LoRA", "path" => "remote/path.safetensors" }]
        end
      end.new,
      sampler_catalog: Class.new do
        def names
          %w[euler_a]
        end
      end.new
    ).call

    assert_includes lists[:lora_names], "ChojuGiga_Illustrious"
    assert_includes lists[:lora_names], "Remote_LoRA"
    assert_includes lists[:prompt_presets].map(&:name), "鳥獣戯画テンプレ"
  end
end
