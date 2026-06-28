# frozen_string_literal: true

require "test_helper"

class SdPromptPlannerTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response, keyword_init: true) do
    def chat(messages:, temperature:, max_tokens:, response_format: nil, read_timeout: nil)
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

  test "salvages truncated json when positive prompt is cut off" do
    client = FakeClient.new(
      response: {
        "choices" => [
          {
            "finish_reason" => "length",
            "message" => {
              "content" => <<~CONTENT
                ```json
                {
                  "positive": "masterpiece, best quality, 1girl, cafe interior",
                  "negative": "worst quality, low quality",
                  "width": 768,
                  "height": 512,
                  "steps": 24,
                  "cfg_scale": 8.5,
                  "seed": 42
              CONTENT
            }
          }
        ]
      }
    )

    skill = PromptSkill.new(body: "system")
    plan = SdPromptPlanner.new(client: client).plan(body: "カフェ", skill: skill)

    assert_equal "masterpiece, best quality, 1girl, cafe interior", plan[:positive]
    assert_equal "worst quality, low quality", plan[:negative]
    assert_equal 768, plan[:width]
    assert_equal 512, plan[:height]
  end

  test "includes retrieved knowledge in user prompt when record is given" do
    chunk = PromptKnowledgeChunk.create!(
      title: "ChojuGiga style",
      body: "chojugiga, emaki, ink outline",
      kind: "style"
    )
    illustration = MemoIllustration.new(body: "鳥獣戯画風のウサギ", sd_model: "pony-v6")
    captured_messages = nil

    client = Class.new do
      define_method(:chat) do |messages:, temperature:, max_tokens:, response_format: nil, read_timeout: nil|
        captured_messages = messages
        {
          "choices" => [{
            "message" => {
              "content" => {
                positive: "masterpiece, chojugiga, rabbit",
                negative: "photorealistic",
                width: 768,
                height: 768,
                steps: 22,
                cfg_scale: 6.0,
                seed: -1
              }.to_json
            }
          }]
        }
      end
    end.new

    retriever = Class.new do
      define_method(:retrieve) { |query| PromptKnowledgeChunk.where(id: chunk.id) }
    end.new

    skill = PromptSkill.new(body: "system")
    plan = SdPromptPlanner.new(client: client, retriever: retriever).plan(
      body: illustration.body,
      skill: skill,
      record: illustration
    )

    user_prompt = captured_messages.last[:content]
    assert_includes user_prompt, "Retrieved knowledge chunks:"
    assert_includes user_prompt, "chojugiga, emaki, ink outline"
    assert_includes plan[:source_chunk_ids], chunk.id
    assert_equal "masterpiece, chojugiga, rabbit", plan[:positive]
  end

  test "parses json from reasoning content when content is empty" do
    client = FakeClient.new(
      response: {
        "choices" => [
          {
            "message" => {
              "content" => "",
              "reasoning_content" => <<~REASONING
                ```json
                {
                  "positive": "masterpiece, best quality, cafe",
                  "negative": "realistic",
                  "width": 512,
                  "height": 512,
                  "steps": 20,
                  "cfg_scale": 7.0,
                  "seed": -1
                }
                ```
              REASONING
            }
          }
        ]
      }
    )

    skill = PromptSkill.new(body: "system")
    plan = SdPromptPlanner.new(client: client).plan(body: "カフェ", skill: skill)

    assert_equal "masterpiece, best quality, cafe", plan[:positive]
    assert_equal "realistic", plan[:negative]
  end

  test "requests max_tokens 4096" do
    calls = []
    client = Object.new
    client.define_singleton_method(:chat) do |messages:, temperature:, max_tokens:, response_format: nil, read_timeout: nil|
      calls << max_tokens
      {
        "choices" => [
          {
            "message" => {
              "content" => "{\"positive\":\"prompt\",\"negative\":\"low quality\"}"
            }
          }
        ]
      }
    end

    skill = PromptSkill.new(body: "system")
    SdPromptPlanner.new(client: client).plan(body: "test", skill: skill)

    assert_equal [4096], calls
  end
end
