# frozen_string_literal: true

require "test_helper"

class LlamaServerUsageResolverTest < ActiveSupport::TestCase
  test "describes bound connections and named application usages" do
    manager = service_connections(:llama_switchd)
    connection = service_connections(:llama_cpp)
    connection.update!(manager_connection: manager, managed_server_id: "main", enabled: true)
    LlmUsageAssignmentSeeds.seed!

    descriptions = LlamaServerUsageResolver.descriptions_for_server(manager, "main")

    assert_equal 1, descriptions.size
    assert_includes descriptions.first, connection.name
    assert_includes descriptions.first, connection.key
    assert_includes descriptions.first, "通常Chat"
  end

  test "ignores disabled and differently bound connections" do
    manager = service_connections(:llama_switchd)
    service_connections(:llama_cpp).update!(manager_connection: manager, managed_server_id: "other")
    service_connections(:gpt_oss).update!(manager_connection: manager, managed_server_id: "main", enabled: false)

    assert_empty LlamaServerUsageResolver.descriptions_for_server(manager, "main")
  end

  test "derives usages from model assignments" do
    LlmUsageAssignmentSeeds.seed!
    connection = service_connections(:llama_cpp)

    labels = LlamaServerUsageResolver.labels_for(connection)

    assert_includes labels, "通常Chat"
    assert_includes labels, "AgentGraphドラフト"
    assert_includes labels, "画像生成style plan"
    assert_not_includes labels, "画像理解"
  end
end
