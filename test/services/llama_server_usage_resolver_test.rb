# frozen_string_literal: true

require "test_helper"

class LlamaServerUsageResolverTest < ActiveSupport::TestCase
  test "describes bound connections and named application usages" do
    manager = service_connections(:llama_switchd)
    connection = service_connections(:llama_cpp)
    connection.update!(manager_connection: manager, managed_server_id: "main", enabled: true)
    AppSetting.instance.update!(default_chat_connection_key: connection.key)

    descriptions = LlamaServerUsageResolver.descriptions_for_server(manager, "main")

    assert_equal 1, descriptions.size
    assert_includes descriptions.first, connection.name
    assert_includes descriptions.first, connection.key
    assert_includes descriptions.first, "既定Chat"
  end

  test "ignores disabled and differently bound connections" do
    manager = service_connections(:llama_switchd)
    service_connections(:llama_cpp).update!(manager_connection: manager, managed_server_id: "other")
    service_connections(:gpt_oss).update!(manager_connection: manager, managed_server_id: "main", enabled: false)

    assert_empty LlamaServerUsageResolver.descriptions_for_server(manager, "main")
  end
end
