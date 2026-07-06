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

  test "update searxng search settings" do
    connection = service_connections(:searxng)

    patch service_connection_path(connection), params: {
      service_connection: {
        name: connection.name,
        base_url: connection.base_url,
        enabled: true,
        sort_order: connection.sort_order,
        searxng_settings: {
          result_count: 3,
          concurrent_searches: 1,
          engines: "duckduckgo,wikipedia",
          retry_count: 0,
          max_searches_per_turn: 1,
          max_fetches_per_turn: 2
        }
      }
    }

    assert_redirected_to service_connection_path(connection)
    settings = connection.reload.searxng_settings
    assert_equal 3, settings.result_count
    assert_equal 1, settings.concurrent_searches
    assert_equal "duckduckgo,wikipedia", settings.engines
    assert_equal 0, settings.retry_count
    assert_equal 1, settings.max_searches_per_turn
    assert_equal 2, settings.max_fetches_per_turn
  end

  test "refresh models syncs openai chat model list" do
    connection = service_connections(:openai)
    connection.update!(enabled: true, api_token: "sk-test", server_model: nil)
    fake_result = ServiceConnectionModelFetcher::Result.new(
      ok: true,
      models: %w[gpt-4o gpt-4o-mini],
      message: "モデル 2 件を取得しました"
    )

    with_fake_model_fetcher(fake_result) do
      post refresh_models_service_connection_path(connection)
    end

    connection.reload
    assert_redirected_to service_connection_path(connection)
    assert_equal %w[gpt-4o gpt-4o-mini], connection.settings["chat_models"]
    assert_equal "gpt-4o", connection.server_model
    assert Model.exists?(provider: "openai", model_id: "gpt-4o")
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

  test "new custom llm form" do
    get new_service_connection_path(custom: 1)

    assert_response :success
    assert_match "カスタム LLM 接続", response.body
    assert_match "llm_", response.body
  end

  test "create custom llm connection" do
    assert_difference -> { ServiceConnection.count }, 1 do
      post service_connections_path, params: {
        custom: 1,
        service_connection: {
          key: "llm_test_server",
          name: "Test Server",
          base_url: "http://balvenie:10012",
          server_model: "test-model",
          enabled: true,
          sort_order: 99
        }
      }
    end

    connection = ServiceConnection.find_by!(key: "llm_test_server")
    assert_redirected_to service_connection_path(connection)
    assert_equal "http://balvenie:10012", NyoyConnectionStore.url(:llm_test_server)
  end

  test "seed_missing registers missing builtin connections" do
    ServiceConnection.where(key: "readability").delete_all

    post seed_missing_service_connections_path

    assert_redirected_to service_connections_path
    assert ServiceConnection.exists?(key: "readability")
    assert_match(/組み込み接続 1 件/, flash[:notice])
  end

  test "destroy custom llm connection" do
    connection = ServiceConnection.create!(
      key: "llm_delete_me",
      name: "Delete Me",
      base_url: "http://example.com:8080",
      server_model: "test-model"
    )

    assert_difference -> { ServiceConnection.count }, -1 do
      delete service_connection_path(connection)
    end

    assert_redirected_to service_connections_path
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
