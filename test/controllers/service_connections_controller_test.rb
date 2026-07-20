# frozen_string_literal: true

require "test_helper"

class ServiceConnectionsControllerTest < ActionDispatch::IntegrationTest
  test "index lists connections" do
    get service_connections_path

    assert_response :success
    assert_match service_connections(:llama_cpp).name, response.body
  end

  test "llama servers shows read only inventory" do
    result = LlamaSwitchdInventory::Result.new(
      servers: [ { "id" => "main", "alias" => "main-model", "port" => 10010, "state" => "ready" } ],
      models: [],
      connections: []
    )
    original = LlamaSwitchdInventory.instance_method(:call)
    LlamaSwitchdInventory.define_method(:call) { result }

    get llama_servers_service_connections_path

    assert_response :success
    assert_select "h1", text: "LLM サーバー"
    assert_match "main-model", response.body
  ensure
    LlamaSwitchdInventory.define_method(:call, original) if defined?(original)
  end

  test "llama servers reports switchd errors" do
    original = LlamaSwitchdInventory.instance_method(:call)
    LlamaSwitchdInventory.define_method(:call) { raise LlamaSwitchdClient::Error, "switchd unavailable" }

    get llama_servers_service_connections_path

    assert_response :success
    assert_match "switchd unavailable", response.body
  ensure
    LlamaSwitchdInventory.define_method(:call, original) if defined?(original)
  end

  test "bind llama server stores binding without changing connection values" do
    connection = service_connections(:llama_cpp)
    original_url = connection.base_url
    original_model = connection.server_model
    original = LlamaSwitchdClient.method(:new)
    client = Object.new
    client.define_singleton_method(:list_servers) { [ { "id" => "main" } ] }
    LlamaSwitchdClient.define_singleton_method(:new) { |**| client }

    patch bind_llama_server_service_connection_path(connection), params: { managed_server_id: "main" }

    assert_redirected_to llama_servers_service_connections_path
    connection.reload
    assert_equal service_connections(:llama_switchd), connection.manager_connection
    assert_equal "main", connection.managed_server_id
    assert_equal original_url, connection.base_url
    assert_equal original_model, connection.server_model
  ensure
    LlamaSwitchdClient.define_singleton_method(:new, original) if defined?(original)
  end

  test "bind llama server rejects unknown server" do
    connection = service_connections(:llama_cpp)
    original = LlamaSwitchdClient.method(:new)
    client = Object.new
    client.define_singleton_method(:list_servers) { [] }
    LlamaSwitchdClient.define_singleton_method(:new) { |**| client }

    patch bind_llama_server_service_connection_path(connection), params: { managed_server_id: "missing" }

    assert_redirected_to llama_servers_service_connections_path
    assert_nil connection.reload.managed_server_id
  ensure
    LlamaSwitchdClient.define_singleton_method(:new, original) if defined?(original)
  end

  test "operate llama server queues allowed action" do
    assert_enqueued_jobs 1, only: LlamaServerOperationJob do
      post operate_llama_server_service_connections_path, params: {
        managed_server_id: "main",
        server_action: "restart"
      }
    end

    assert_redirected_to llama_servers_service_connections_path
    operation = LlamaServerOperation.order(:id).last
    assert_equal "main", operation.managed_server_id
    assert_equal "restart", operation.action
    assert_equal "queued", operation.status
  end

  test "operate llama server rejects unsupported action" do
    assert_no_difference -> { LlamaServerOperation.count } do
      post operate_llama_server_service_connections_path, params: {
        managed_server_id: "main",
        server_action: "delete"
      }
    end

    assert_redirected_to llama_servers_service_connections_path
    assert_match(/Action/, flash[:alert])
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

  test "update prompt conversion settings for chat backend" do
    connection = service_connections(:llama_cpp)

    patch service_connection_path(connection), params: {
      service_connection: {
        name: connection.name,
        base_url: connection.base_url,
        server_model: connection.server_model,
        enabled: true,
        sort_order: connection.sort_order,
        prompt_conversion_settings: {
          json_schema: "off",
          temperature: "0.15",
          top_p: "0.8",
          max_tokens: "700",
          reasoning_effort: "high",
          enable_thinking: "false"
        }
      }
    }

    assert_redirected_to service_connection_path(connection)
    pcs = connection.reload.prompt_conversion_settings
    assert_equal "off", pcs.json_schema
    assert_in_delta 0.15, pcs.temperature
    assert_in_delta 0.8, pcs.top_p
    assert_equal 700, pcs.max_tokens
    assert_equal "high", pcs.reasoning_effort
    assert_equal "false", pcs.enable_thinking
  end

  test "load_sampling returns props sampling as json" do
    connection = service_connections(:llama_cpp)
    original = ServiceConnectionPropsFetcher.instance_method(:call)
    ServiceConnectionPropsFetcher.define_method(:call) do
      ServiceConnectionPropsFetcher::Result.new(
        ok: true,
        sampling: LlmSamplingParams.from("temperature" => 0.7, "top_p" => 0.8),
        raw_props: {},
        message: "ok"
      )
    end

    post load_sampling_service_connection_path(connection, format: :json)

    assert_response :success
    body = response.parsed_body
    assert body["ok"]
    assert_in_delta 0.7, body.dig("sampling", "temperature")
    assert_in_delta 0.8, body.dig("sampling", "top_p")
  ensure
    ServiceConnectionPropsFetcher.define_method(:call, original) if defined?(original)
  end

  test "update searfront api token" do
    connection = service_connections(:searfront)

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
    assert_equal "searx_saved_token", NyoyConnectionStore.api_token(:searfront)
  end

  test "update searfront search settings" do
    connection = service_connections(:searfront)
    previous_engines = connection.searfront_settings.engines

    patch service_connection_path(connection), params: {
      service_connection: {
        name: connection.name,
        base_url: connection.base_url,
        enabled: true,
        sort_order: connection.sort_order,
        searfront_settings: {
          result_count: 3,
          concurrent_searches: 1,
          engines: "ignored,client,value",
          retry_count: 0,
          max_searches_per_turn: 1,
          max_fetches_per_turn: 2
        }
      }
    }

    assert_redirected_to service_connection_path(connection)
    settings = connection.reload.searfront_settings
    assert_equal 3, settings.result_count
    assert_equal 1, settings.concurrent_searches
    assert_equal previous_engines, settings.engines
    assert_equal 0, settings.retry_count
    assert_equal 1, settings.max_searches_per_turn
    assert_equal 2, settings.max_fetches_per_turn
  end

  test "edit searfront form omits engines field" do
    connection = service_connections(:searfront)

    get edit_service_connection_path(connection)

    assert_response :success
    assert_select "input[name='service_connection[searfront_settings][result_count]']"
    assert_select "input[name='service_connection[searfront_settings][engines]']", count: 0
  end

  test "show searfront omits engines row" do
    connection = service_connections(:searfront)

    get service_connection_path(connection)

    assert_response :success
    assert_select "dt", text: "web_search 上限"
    assert_select "dt", text: "検索エンジン", count: 0
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
    assert_equal %w[gpt-4o gpt-4o-mini], connection.settings["chat_models_catalog"]
    assert_equal %w[gpt-4o gpt-4o-mini], connection.settings["chat_models"]
    assert_equal "gpt-4o", connection.server_model
    assert Model.exists?(provider: "openai", model_id: "gpt-4o")
  end

  test "update enables OpenAI connection with environment API token" do
    original = Rails.application.config.x.nyoy.openai_api_key
    Rails.application.config.x.nyoy.openai_api_key = "sk-env"
    connection = service_connections(:openai)
    connection.update!(enabled: false, api_token: nil)

    patch service_connection_path(connection), params: {
      service_connection: {
        name: connection.name,
        base_url: connection.base_url,
        server_model: connection.server_model,
        api_token: "",
        enabled: true,
        sort_order: connection.sort_order
      }
    }

    assert_redirected_to service_connection_path(connection)
    assert connection.reload.enabled?
    assert_nil connection.api_token

    get service_connection_path(connection)
    assert_select "dd", text: "環境変数（OPENAI_CHAT_API_KEY）"

    get edit_service_connection_path(connection)
    assert_response :success
    assert_select ".kb-status-success", text: /OPENAI_CHAT_API_KEY が設定済み/
  ensure
    Rails.application.config.x.nyoy.openai_api_key = original
  end

  test "update openai chat model enabled flags" do
    connection = service_connections(:openai)
    connection.update!(
      enabled: true,
      api_token: "sk-test",
      settings: {
        "chat_models_catalog" => %w[gpt-4o gpt-4o-mini gpt-3.5-turbo],
        "chat_models" => %w[gpt-4o gpt-4o-mini gpt-3.5-turbo]
      }
    )
    ChatModelCatalog.seed!

    patch openai_chat_models_service_connection_path(connection), params: {
      service_connection: {
        openai_chat_models: {
          enabled: {
            "gpt-4o" => "1",
            "gpt-4o-mini" => "0",
            "gpt-3.5-turbo" => "1"
          }
        }
      }
    }

    assert_redirected_to service_connection_path(connection)
    connection.reload
    assert_equal %w[gpt-3.5-turbo gpt-4o], connection.settings["chat_models"]
    assert_equal %w[gpt-3.5-turbo gpt-4o gpt-4o-mini], connection.settings["chat_models_catalog"]
    assert_includes ChatModelCatalog.definitions.map(&:model_id), "gpt-4o"
    assert_not_includes ChatModelCatalog.definitions.map(&:model_id), "gpt-4o-mini"
  end

  test "refresh models updates server model from api" do
    connection = service_connections(:gpt_oss)
    connection.update!(server_model: "old-model")
    fake_result = ServiceConnectionModelFetcher::Result.new(ok: true, models: [ "gpt-oss-20b" ], message: "モデル 1 件を取得しました")

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
