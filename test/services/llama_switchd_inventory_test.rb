# frozen_string_literal: true

require "test_helper"

class LlamaSwitchdInventoryTest < ActiveSupport::TestCase
  test "compares connection port and alias without updating it" do
    connection = service_connections(:llama_cpp)
    connection.update!(base_url: "http://balvenie:10010", server_model: "old-alias")
    client = fake_client(
      servers: [
        { "id" => "main", "port" => 10010, "alias" => "new-alias" },
        { "id" => "vision", "port" => 10021, "alias" => "qwen2.5-vl-3b" }
      ],
      models: [ { "path" => "/models/main.gguf" } ]
    )

    result = LlamaSwitchdInventory.new(service_connections(:llama_switchd), client: client).call
    comparison = result.connections.find { |item| item.connection == connection }

    assert_equal :port_only, comparison.status
    assert comparison.port_matches
    assert_not comparison.alias_matches
    assert_equal "old-alias", connection.reload.server_model
    assert_equal 1, result.models.size
  end

  test "reports exact match" do
    connection = service_connections(:vision_llama)
    client = fake_client(
      servers: [ { "id" => "vision", "port" => 10021, "alias" => connection.server_model } ],
      models: []
    )

    result = LlamaSwitchdInventory.new(service_connections(:llama_switchd), client: client).call
    comparison = result.connections.find { |item| item.connection == connection }

    assert_equal :exact, comparison.status
  end

  test "excludes remote OpenAI connection" do
    result = LlamaSwitchdInventory.new(
      service_connections(:llama_switchd),
      client: fake_client(servers: [], models: [])
    ).call

    assert_not_includes result.connections.map { |item| item.connection.key }, "openai"
  end

  private

  def fake_client(servers:, models:)
    Object.new.tap do |client|
      client.define_singleton_method(:list_servers) { servers }
      client.define_singleton_method(:list_models) { models }
    end
  end
end
