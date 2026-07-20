# frozen_string_literal: true

require "test_helper"

class LlamaSwitchdConnectionSyncTest < ActiveSupport::TestCase
  test "syncs data plane URL and alias from bound server" do
    connection = service_connections(:llama_cpp)
    connection.update!(
      manager_connection: service_connections(:llama_switchd),
      managed_server_id: "main"
    )
    original = LlamaSwitchdClient.method(:new)
    client = Object.new
    client.define_singleton_method(:get_server) do |id|
      raise unless id == "main"

      { "ok" => true, "server" => { "id" => "main", "port" => 10110, "alias" => "main-alias" } }
    end
    LlamaSwitchdClient.define_singleton_method(:new) { |**| client }

    LlamaSwitchdConnectionSync.new(connection).call

    connection.reload
    assert_equal "http://balvenie:10110", connection.base_url
    assert_equal "main-alias", connection.server_model
  ensure
    LlamaSwitchdClient.define_singleton_method(:new, original) if defined?(original)
  end

  test "requires a binding" do
    connection = service_connections(:llama_cpp)
    connection.update!(manager_connection: nil, managed_server_id: nil)

    assert_raises(LlamaSwitchdClient::Error) do
      LlamaSwitchdConnectionSync.new(connection).call
    end
  end
end
