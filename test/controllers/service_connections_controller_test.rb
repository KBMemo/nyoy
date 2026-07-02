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

  test "update searxng api token" do
    connection = service_connections(:searxng)

    patch service_connection_path(connection), params: {
      service_connection: {
        name: connection.name,
        base_url: connection.base_url,
        api_token: "searx_saved_token",
        enabled: true,
        sort_order: connection.sort_order
      }
    }

    assert_redirected_to service_connection_path(connection)
    assert_equal "searx_saved_token", connection.reload.api_token
    assert_equal "searx_saved_token", NyoyConnectionStore.api_token(:searxng)
  end

  test "refresh models updates server model from api" do
    connection = service_connections(:gpt_oss)
    connection.update!(server_model: "old-model")
    fake_result = ServiceConnectionModelFetcher::Result.new(ok: true, models: ["gpt-oss-20b"], message: "モデル 1 件を取得しました")

    with_fake_model_fetcher(fake_result) do
      post refresh_models_service_connection_path(connection)
    end

    assert_redirected_to service_connection_path(connection)
    assert_equal "モデル 1 件を取得しました", flash[:notice]
    assert_equal "gpt-oss-20b", connection.reload.server_model
  end

  test "refresh models keeps current server model when api contains it" do
    connection = service_connections(:gpt_oss)
    connection.update!(server_model: "gpt-oss-20b")
    fake_result = ServiceConnectionModelFetcher::Result.new(ok: true, models: %w[gpt-oss-20b gpt-oss-120b], message: "モデル 2 件を取得しました")

    with_fake_model_fetcher(fake_result) do
      post refresh_models_service_connection_path(connection)
    end

    assert_redirected_to service_connection_path(connection)
    assert_equal "gpt-oss-20b", connection.reload.server_model
  end

  test "refresh models reports failure" do
    connection = service_connections(:sd_cpp)
    fake_result = ServiceConnectionModelFetcher::Result.new(ok: false, models: [], message: "この接続種別はモデル取得に対応していません")

    with_fake_model_fetcher(fake_result) do
      post refresh_models_service_connection_path(connection)
    end

    assert_redirected_to service_connection_path(connection)
    assert_equal "この接続種別はモデル取得に対応していません", flash[:alert]
  end

  test "builtin connection cannot be destroyed" do
    connection = service_connections(:llama_cpp)

    assert_no_difference -> { ServiceConnection.count } do
      delete service_connection_path(connection)
    end

    assert_redirected_to service_connection_path(connection)
  end

  private

  def with_fake_model_fetcher(result)
    fake_class = Class.new do
      define_method(:initialize) { |*| }
      define_method(:call) { result }
    end
    original_new = ServiceConnectionModelFetcher.method(:new)
    ServiceConnectionModelFetcher.singleton_class.define_method(:new) { |*| fake_class.new }

    yield
  ensure
    ServiceConnectionModelFetcher.singleton_class.define_method(:new, original_new)
  end
end
