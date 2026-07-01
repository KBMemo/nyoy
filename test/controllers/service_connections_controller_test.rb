# frozen_string_literal: true

require "test_helper"

class ServiceConnectionsControllerTest < ActionDispatch::IntegrationTest
  test "index lists connections" do
    get service_connections_path

    assert_response :success
    assert_match service_connections(:llama_cpp).name, response.body
  end

  test "update connection" do
    connection = service_connections(:vision_llama)

    patch service_connection_path(connection), params: {
      service_connection: {
        name: "Vision updated",
        base_url: "http://balvenie:10022",
        server_model: "qwen2.5-vl-3b",
        enabled: true,
        sort_order: connection.sort_order
      }
    }

    assert_redirected_to service_connection_path(connection)
    connection.reload
    assert_equal "http://balvenie:10022", connection.base_url
    assert_equal "http://balvenie:10022", NyoyConnectionStore.url(:vision_llama)
  end

  test "probe reports success" do
    connection = service_connections(:llama_cpp)
    fake_result = ServiceConnectionProbe::Result.new(ok: true, message: "サーバーに接続できました", latency_ms: 12)

    with_fake_probe(fake_result) do
      post probe_service_connection_path(connection)
    end

    assert_redirected_to service_connection_path(connection)
    assert_equal "疎通確認 OK（12ms）: サーバーに接続できました", flash[:notice]
  end

  test "probe reports failure" do
    connection = service_connections(:sd_cpp)
    fake_result = ServiceConnectionProbe::Result.new(ok: false, message: "接続できませんでした", latency_ms: 5)

    with_fake_probe(fake_result) do
      post probe_service_connection_path(connection)
    end

    assert_redirected_to service_connection_path(connection)
    assert_equal "疎通確認 NG（5ms）: 接続できませんでした", flash[:alert]
  end

  test "builtin connection cannot be destroyed" do
    connection = service_connections(:llama_cpp)

    assert_no_difference -> { ServiceConnection.count } do
      delete service_connection_path(connection)
    end

    assert_redirected_to service_connection_path(connection)
  end

  private

  def with_fake_probe(result)
    fake_class = Class.new do
      define_method(:initialize) { |*| }
      define_method(:call) { result }
    end
    original_new = ServiceConnectionProbe.method(:new)
    ServiceConnectionProbe.singleton_class.define_method(:new) { |*| fake_class.new }

    yield
  ensure
    ServiceConnectionProbe.singleton_class.define_method(:new, original_new)
  end
end
