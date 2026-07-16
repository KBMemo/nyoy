# frozen_string_literal: true

require "test_helper"

class McpExtensionToolsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ChatModelCatalog.seed!
    NyoyConnectionStore.clear_cache!
  end

  test "available when sd_cpp connection is enabled" do
    assert Mcp::ExtensionTools.available?
  end

  test "not available when sd_cpp is disabled" do
    service_connections(:sd_cpp).update!(enabled: false)
    NyoyConnectionStore.clear_cache!

    assert_not Mcp::ExtensionTools.available?
    assert_empty Mcp::ExtensionTools.mcp_tools
  end

  test "list_prompt_styles returns enabled styles" do
    tool = Mcp::ExtensionTools.list_prompt_styles_tool
    response = tool.call

    payload = JSON.parse(response.content.first[:text])
    style_ids = payload.fetch("styles").map { |item| item["style_id"] }

    assert_includes style_ids, prompt_styles(:chojugiga).style_id
  end

  test "list_image_generation_options returns styles models and templates" do
    tool = Mcp::ExtensionTools.list_image_generation_options_tool
    response = tool.call

    payload = JSON.parse(response.content.first[:text])

    assert_includes payload["generation_flows"], "draft"
    assert_includes payload["generation_flows"], "direct"
    assert_includes payload.fetch("styles").map { |item| item["style_id"] }, prompt_styles(:chojugiga).style_id

    profile = payload.fetch("sd_model_profiles").find { |item| item["id"] == sd_model_profiles(:pony).id }
    assert_equal "pony-v6", profile["key"]
    assert_equal "pony", profile["family"]
    assert_includes profile["sampler_names"], "euler_a"
    assert_equal 768, profile.dig("default_params", "width")

    template = payload.fetch("sd_prompt_templates").find { |item| item["id"] == sd_prompt_templates(:pony_family).id }
    assert_equal "Pony XL 向け", template["name"]
    assert_equal "pony", template["family"]
  end

  test "generate_image enqueues job and returns id" do
    assert_enqueued_with(job: GenerateImageJob) do
      response = Mcp::ExtensionTools.generate_image_tool.call(
        japanese_prompt: "静物スケッチのテスト"
      )
      payload = JSON.parse(response.content.first[:text])

      assert payload["id"].present?
      assert_equal "pending", payload["status"]
      assert payload["show_path"].present?
      assert_equal "draft", payload["generation_flow"]
    end
  end

  test "generate_image supports direct flow" do
    profile = sd_model_profiles(:pony)

    assert_enqueued_with(job: GenerateImageJob) do
      response = Mcp::ExtensionTools.generate_image_tool.call(
        japanese_prompt: "少女の肖像",
        generation_flow: "direct",
        sd_model_profile_id: profile.id,
        prompt: "1girl, masterpiece",
        negative_prompt: "low quality",
        width: 768,
        height: 768,
        steps: 24,
        cfg_scale: 6.0,
        sampler_name: "euler_a"
      )
      payload = JSON.parse(response.content.first[:text])

      assert_not response.error?
      assert payload["id"].present?
      assert_equal "pending", payload["status"]
      assert_equal "direct", payload["generation_flow"]
      assert_match(/completed/, payload["note"])

      generation = ImageGeneration.find(payload["id"])
      assert generation.direct_flow?
      assert_equal profile, generation.sd_model_profile
      assert_equal "1girl, masterpiece", generation.prompt
      assert_equal "low quality", generation.negative_prompt
      assert_equal 768, generation.width
      assert_equal 24, generation.steps
    end
  end

  test "generate_image direct flow requires model profile" do
    response = Mcp::ExtensionTools.generate_image_tool.call(
      japanese_prompt: "少女の肖像",
      generation_flow: "direct"
    )

    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_match(/sd_model_profile_id/, payload["error"])
  end

  test "get_image_generation returns summary" do
    generation = ImageGeneration.create!(
      japanese_prompt: "テスト",
      status: "awaiting_selection",
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      loras: "[]",
      draft_batch_size: 4,
      refine_denoising_strength: 0.4,
      enable_hires: true,
      hires_upscaler: "Latent",
      hires_scale: 1.5,
      hires_denoising_strength: 0.35
    )

    response = Mcp::ExtensionTools.get_image_generation_tool.call(id: generation.id)
    payload = JSON.parse(response.content.first[:text])

    assert_equal generation.id, payload["id"]
    assert_equal "awaiting_selection", payload["status"]
    assert payload["awaiting_selection"]
    assert_equal "draft", payload["generation_flow"]
  end

  test "get_image_generation returns error for missing id" do
    response = Mcp::ExtensionTools.get_image_generation_tool.call(id: 0)

    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert payload["error"].present?
  end

  test "refine_image enqueues job when draft exists" do
    generation = ImageGeneration.create!(
      japanese_prompt: "テスト",
      status: "awaiting_selection",
      prompt: "test prompt",
      resolved_negative_prompt: "bad",
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      loras: "[]",
      draft_batch_size: 4,
      refine_denoising_strength: 0.4,
      enable_hires: true,
      hires_upscaler: "Latent",
      hires_scale: 1.5,
      hires_denoising_strength: 0.35
    )
    generation.drafts.attach(
      io: StringIO.new("fake"),
      filename: "draft.png",
      content_type: "image/png"
    )

    assert_enqueued_with(job: RefineImageJob) do
      response = Mcp::ExtensionTools.refine_image_tool.call(id: generation.id, draft_index: 0)
      payload = JSON.parse(response.content.first[:text])

      assert_equal "refining", payload["status"]
      assert_equal 0, payload["selected_draft_index"]
    end
  end

  test "refine_image rejects invalid draft_index" do
    generation = ImageGeneration.create!(
      japanese_prompt: "テスト",
      status: "awaiting_selection",
      width: 768,
      height: 768,
      steps: 22,
      cfg_scale: 6.0,
      sampler_name: "euler_a",
      loras: "[]",
      draft_batch_size: 4,
      refine_denoising_strength: 0.4,
      enable_hires: true,
      hires_upscaler: "Latent",
      hires_scale: 1.5,
      hires_denoising_strength: 0.35
    )

    response = Mcp::ExtensionTools.refine_image_tool.call(id: generation.id, draft_index: 0)

    assert response.error?
  end
end
