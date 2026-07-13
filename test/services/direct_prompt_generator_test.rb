# frozen_string_literal: true

require "test_helper"

class DirectPromptGeneratorTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response, :captured, keyword_init: true) do
    def chat(messages:, temperature:, max_tokens:, response_format: nil, chat_template_kwargs: nil, sampling: nil, read_timeout: nil, **)
      captured[:messages] = messages if captured
      captured[:temperature] = temperature if captured
      captured[:max_tokens] = max_tokens if captured
      captured[:response_format] = response_format if captured
      captured[:chat_template_kwargs] = chat_template_kwargs if captured
      captured[:sampling] = sampling if captured
      response
    end
  end

  def llama_response(json)
    { "choices" => [{ "message" => { "content" => json.to_json } }] }
  end

  test "returns prompt and negative_prompt from llama JSON" do
    captured = {}
    client = FakeClient.new(
      response: llama_response(
        prompt: "1girl, masterpiece",
        negative_prompt: "low quality, blurry"
      ),
      captured: captured
    )

    result = DirectPromptGenerator.new(client: client).generate(
      "少女の肖像",
      sd_model_profile: sd_model_profiles(:pony)
    )

    assert_equal "1girl, masterpiece", result[:prompt]
    assert_equal "low quality, blurry", result[:negative_prompt]
    assert_equal sd_prompt_templates(:pony_family).id, result[:sd_prompt_template_id]
    assert_includes captured[:messages].first[:content], DirectPromptGenerator::SYSTEM_PREFIX
    assert_includes captured[:messages].first[:content], sd_prompt_templates(:pony_family).body
  end

  test "uses explicit template override" do
    captured = {}
    client = FakeClient.new(
      response: llama_response(prompt: "test prompt", negative_prompt: "test negative"),
      captured: captured
    )
    global = sd_prompt_templates(:global_default)

    result = DirectPromptGenerator.new(client: client).generate(
      "テスト",
      sd_model_profile: sd_model_profiles(:pony),
      sd_prompt_template: global
    )

    assert_equal global.id, result[:sd_prompt_template_id]
    assert_includes captured[:messages].first[:content], global.body
  end

  test "attaches json schema when connection supports it" do
    captured = {}
    client = FakeClient.new(
      response: llama_response(prompt: "a", negative_prompt: "b"),
      captured: captured
    )

    with_json_schema_enabled do
      DirectPromptGenerator.new(client: client, connection_key: "llama_cpp").generate(
        "テスト",
        sd_model_profile: sd_model_profiles(:pony)
      )
    end

    assert_equal DirectPromptJsonSchema.build, captured[:response_format]
    refute_includes captured[:messages].last[:content], "Return JSON with keys"
  end

  test "falls back to user prompt JSON instruction without schema support" do
    captured = {}
    client = FakeClient.new(
      response: llama_response(prompt: "a", negative_prompt: "b"),
      captured: captured
    )

    with_json_schema_enabled do
      DirectPromptGenerator.new(client: client, connection_key: "gpt_oss").generate(
        "テスト",
        sd_model_profile: sd_model_profiles(:pony)
      )
    end

    assert_nil captured[:response_format]
    assert_includes captured[:messages].last[:content], "Return JSON with keys: prompt, negative_prompt"
  end

  test "raises when japanese prompt is blank" do
    assert_raises(DirectPromptGenerator::Error, match: /japanese_prompt required/) do
      DirectPromptGenerator.new(client: FakeClient.new(response: {})).generate(
        "  ",
        sd_model_profile: sd_model_profiles(:pony)
      )
    end
  end

  test "raises when prompt field is missing" do
    client = FakeClient.new(
      response: llama_response(prompt: "", negative_prompt: "blurry")
    )

    assert_raises(DirectPromptGenerator::Error, match: /prompt missing/) do
      DirectPromptGenerator.new(client: client).generate(
        "テスト",
        sd_model_profile: sd_model_profiles(:pony)
      )
    end
  end

  test "raises when negative_prompt field is missing" do
    client = FakeClient.new(
      response: llama_response(prompt: "1girl", negative_prompt: "")
    )

    assert_raises(DirectPromptGenerator::Error, match: /negative_prompt missing/) do
      DirectPromptGenerator.new(client: client).generate(
        "テスト",
        sd_model_profile: sd_model_profiles(:pony)
      )
    end
  end

  test "build_system_prompt combines prefix and template body" do
    template = sd_prompt_templates(:pony_family)
    system = DirectPromptGenerator.build_system_prompt(template)

    assert_includes system, DirectPromptGenerator::SYSTEM_PREFIX
    assert_includes system, template.body
  end

  test "applies connection prompt conversion settings" do
    service_connections(:llama_cpp).update!(
      settings: {
        "prompt_conversion" => {
          "json_schema" => "off",
          "temperature" => 0.15,
          "top_p" => 0.8,
          "max_tokens" => 400,
          "enable_thinking" => "false"
        }
      }
    )

    captured = {}
    client = FakeClient.new(
      response: llama_response(prompt: "a", negative_prompt: "b"),
      captured: captured
    )

    with_json_schema_enabled do
      DirectPromptGenerator.new(client: client, connection_key: "llama_cpp").generate(
        "テスト",
        sd_model_profile: sd_model_profiles(:pony)
      )
    end

    assert_nil captured[:response_format]
    assert_in_delta 0.15, captured[:temperature]
    assert_equal 400, captured[:max_tokens]
    assert_equal({ "enable_thinking" => false }, captured[:chat_template_kwargs])
    assert_in_delta 0.8, captured[:sampling].top_p
    assert_includes captured[:messages].last[:content], "Return JSON with keys: prompt, negative_prompt"
  end

  private

  def with_json_schema_enabled
    original = Rails.application.config.x.nyoy.llama_json_schema
    Rails.application.config.x.nyoy.llama_json_schema = true
    yield
  ensure
    Rails.application.config.x.nyoy.llama_json_schema = original
  end
end
