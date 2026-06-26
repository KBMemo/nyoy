# frozen_string_literal: true

require "test_helper"

class PromptSpecGeneratorTest < ActiveSupport::TestCase
  test "builds validated prompt spec from rag and llama response" do
    PromptKnowledgeChunk.create!(
      title: "ChojuGiga",
      body: "chojugiga, emaki, ink outline",
      kind: "style"
    )

    prompt_loras(:chojugiga)

    generation = ImageGeneration.new(
      japanese_prompt: "鳥獣戯画風のウサギ",
      sd_model: "pony-v6",
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      loras: "[]"
    )

    llama_response = {
      "choices" => [{
        "message" => {
          "content" => {
            positive_prompt: "masterpiece, chojugiga, rabbit",
            negative_prompt: "blurry, text",
            model_family: "pony-v6",
            sampler: "euler_a",
            loras: [{ name: "ChojuGiga_Illustrious", weight: 0.8 }],
            source_chunk_ids: [1]
          }.to_json
        }
      }]
    }

    llama_client = Class.new do
      define_method(:initialize) { |**| }
      define_method(:chat) { |**| llama_response }
    end.new

    allowed_lists = Class.new do
      define_method(:call) do
        {
          lora_entries: [{ "name" => "ChojuGiga_Illustrious", "path" => "chojugiga/ChojuGiga_Illustrious.safetensors" }],
          lora_names: ["ChojuGiga_Illustrious"],
          samplers: %w[euler_a],
          models: %w[pony-v6],
          prompt_presets: [],
          lora_dictionary: PromptLora.all.to_a
        }
      end
    end.new

    spec = PromptSpecGenerator.new(
      generation: generation,
      client: llama_client,
      allowed_lists: allowed_lists
    ).call

    assert_equal "masterpiece, chojugiga, rabbit", spec.positive_prompt
    assert_equal "ChojuGiga_Illustrious", spec.loras.first["name"]
    assert spec.source_chunk_ids.any?
  end

  test "passes json schema response_format when enabled" do
    generation = ImageGeneration.new(
      japanese_prompt: "test",
      sd_model: "pony-v6",
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      loras: "[]"
    )

    captured = {}
    llama_client = Class.new do
      define_method(:initialize) { |**| }
      define_method(:chat) do |**kwargs|
        captured.replace(kwargs)
        {
          "choices" => [{
            "message" => {
              "content" => {
                positive_prompt: "test",
                negative_prompt: "bad",
                model_family: "pony-v6",
                sampler: "euler_a",
                loras: [],
                source_chunk_ids: []
              }.to_json
            }
          }]
        }
      end
    end.new

    allowed_lists = Class.new do
      define_method(:call) do
        {
          lora_entries: [],
          lora_names: [],
          samplers: %w[euler_a],
          models: %w[pony-v6],
          prompt_presets: [],
          lora_dictionary: []
        }
      end
    end.new

    PromptSpecGenerator.new(
      generation: generation,
      client: llama_client,
      allowed_lists: allowed_lists
    ).call

    assert_equal "json_schema", captured[:response_format][:type]
    assert_equal "prompt_spec", captured[:response_format][:json_schema][:name]
  end
end
