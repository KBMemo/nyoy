# frozen_string_literal: true

require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    ChatModelCatalog.seed!
    NyoyConnectionStore.clear_cache!
    ChatTools::Registry.reset_client!
    @original_token = Rails.application.config.x.nyoy.mcp_api_token
    Rails.application.config.x.nyoy.mcp_api_token = "test-mcp-token"
  end

  teardown do
    Rails.application.config.x.nyoy.mcp_api_token = @original_token
    ChatTools::Registry.reset_client!
  end

  test "returns not found when MCP is disabled" do
    Rails.application.config.x.nyoy.mcp_api_token = nil

    post mcp_path, params: initialize_payload.to_json, headers: json_headers

    assert_response :not_found
  end

  test "returns unauthorized without bearer token" do
    post mcp_path, params: initialize_payload.to_json, headers: json_headers

    assert_response :unauthorized
  end

  test "initialize returns server capabilities" do
    post mcp_path,
         params: initialize_payload.to_json,
         headers: json_headers.merge("Authorization" => "Bearer test-mcp-token")

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "nyoy", body.dig("result", "serverInfo", "name")
    assert body.dig("result", "capabilities", "tools")
  end

  test "tools list includes configured chat tools" do
    post mcp_path,
         params: tools_list_payload.to_json,
         headers: json_headers.merge("Authorization" => "Bearer test-mcp-token")

    assert_response :success
    tools = JSON.parse(response.body).dig("result", "tools")
    names = tools.map { |tool| tool["name"] }

    assert_includes names, "fetch_url"
    assert_includes names, "search_memos"
    assert_includes names, "web_search"
    assert_includes names, "list_sampling_presets"
    assert_includes names, "apply_sampling_preset"
    assert_includes names, "generate_image"
    assert_includes names, "list_prompt_styles"
    assert_includes names, "refine_image"
    assert_includes names, "run_research_graph"
    assert_includes names, "get_research_graph"
    refute_includes names, "resume_research_graph"
  end

  test "tools call delegates to chat tool implementation" do
    fake_client = Object.new
    fake_client.define_singleton_method(:list_memos) do |**|
      { "memos" => [{ "uid" => "01J8X2K3M4N5P6Q7R8S9T0UVWX", "title" => "旅行" }] }
    end
    original_client = ChatTools::Registry.method(:client)
    ChatTools::Registry.define_singleton_method(:client) { fake_client }

    post mcp_path,
         params: tools_call_payload(
           name: "search_memos",
           arguments: { q: "旅行" }
         ).to_json,
         headers: json_headers.merge("Authorization" => "Bearer test-mcp-token")

    assert_response :success, -> { "body=#{response.body}" }
    parsed = JSON.parse(response.body)
    assert_nil parsed["error"], -> { parsed.inspect }
    content = parsed.dig("result", "content", 0, "text")
    assert content.present?, -> { parsed.inspect }
    payload = JSON.parse(content)

    assert_equal "旅行", payload.dig("memos", 0, "title")
  ensure
    ChatTools::Registry.define_singleton_method(:client, original_client) if defined?(original_client)
  end

  private

  def json_headers
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end

  def initialize_payload
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: { name: "test", version: "0.1.0" }
      }
    }
  end

  def tools_list_payload
    {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list",
      params: {}
    }
  end

  def tools_call_payload(name:, arguments:)
    {
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: {
        name: name,
        arguments: arguments
      }
    }
  end
end
