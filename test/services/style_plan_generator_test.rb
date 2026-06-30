# frozen_string_literal: true

require "test_helper"

class StylePlanGeneratorTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response, :captured, keyword_init: true) do
    def chat(messages:, temperature:, max_tokens:, response_format: nil, read_timeout: nil)
      captured[:messages] = messages if captured
      captured[:response_format] = response_format if captured
      response
    end
  end

  FakeRetriever = Struct.new(:chunks, keyword_init: true) do
    def retrieve(_query)
      chunks
    end
  end

  def llama_response(json)
    { "choices" => [{ "message" => { "content" => json.to_json } }] }
  end

  test "returns a plan and lists available styles to the model" do
    captured = {}
    client = FakeClient.new(
      response: llama_response(
        style_id: "chojugiga_emaki",
        subject_prompt: "rabbit and frog",
        negative_extra: "busy background",
        aspect_ratio: "square"
      ),
      captured: captured
    )

    plan = StylePlanGenerator.new(
      flow: :memo,
      client: client,
      retriever: FakeRetriever.new(chunks: [])
    ).call("ウサギとカエル")

    assert_equal "chojugiga_emaki", plan.style_id
    assert_equal "rabbit and frog", plan.subject_prompt
    assert_equal "busy background", plan.negative_extra
    assert_equal "square", plan.aspect_ratio
    assert_includes captured[:messages].last[:content], "chojugiga_emaki"
  end

  test "raises when query is blank" do
    assert_raises(StylePlanGenerator::Error) do
      StylePlanGenerator.new(flow: :memo, client: FakeClient.new(response: {}),
                             retriever: FakeRetriever.new(chunks: [])).call("  ")
    end
  end

  test "raises on unknown style_id from llama" do
    client = FakeClient.new(
      response: llama_response(style_id: "ghost", subject_prompt: "x", negative_extra: "", aspect_ratio: "square")
    )

    assert_raises(StylePlanGenerator::Error) do
      StylePlanGenerator.new(flow: :memo, client: client,
                             retriever: FakeRetriever.new(chunks: [])).call("テスト")
    end
  end

  test "forced_style_id restricts available styles" do
    captured = {}
    client = FakeClient.new(
      response: llama_response(
        style_id: "chojugiga_emaki", subject_prompt: "x", negative_extra: "", aspect_ratio: "square"
      ),
      captured: captured
    )

    StylePlanGenerator.new(flow: :memo, client: client,
                           retriever: FakeRetriever.new(chunks: [])).call("テスト", forced_style_id: "chojugiga_emaki")

    enum = captured[:response_format][:json_schema][:schema][:properties][:style_id][:enum]
    assert_equal ["chojugiga_emaki"], enum
  end

  test "repairs truncated json from llama" do
    truncated = '{"style_id":"chojugiga_emaki","subject_prompt":"rabbit","negative_extra":"busy background, photorealistic, 3d, anime, detailed face'
    client = FakeClient.new(response: { "choices" => [{ "message" => { "content" => truncated } }] })

    plan = StylePlanGenerator.new(
      flow: :memo,
      client: client,
      retriever: FakeRetriever.new(chunks: [])
    ).call("余白多め、パステル水彩背景、シンプルな人物シルエット")

    assert_equal "chojugiga_emaki", plan.style_id
    assert_equal "rabbit", plan.subject_prompt
    assert_includes plan.negative_extra, "busy background"
    assert_equal "square", plan.aspect_ratio
  end
end
