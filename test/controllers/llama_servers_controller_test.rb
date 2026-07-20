# frozen_string_literal: true

require "test_helper"

class LlamaServersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_llama_server_admin }

  test "new renders typed definition form" do
    with_client(fake_client) do
      get new_llama_server_path
    end

    assert_response :success
    assert_select "input[name='llama_server_definition[server_id]'][required]"
    assert_select "input[name='llama_server_definition[port]'][type='number']"
    assert_select "input[name='llama_server_definition[source_type]'][type='radio']", count: 2
    assert_select "input[name='llama_server_definition[llama_args]']", count: 0
  end

  test "create queues typed definition" do
    assert_enqueued_jobs 1, only: LlamaServerOperationJob do
      post llama_servers_path, params: valid_params
    end

    assert_redirected_to llama_servers_service_connections_path
    operation = LlamaServerOperation.recent.first
    assert_equal "create", operation.action
    assert_equal "new-model", operation.managed_server_id
    assert_equal 10_150, operation.request_payload.dig("values", "PORT")
    assert_equal "/models/new.gguf", operation.request_payload.dig("values", "MODEL")
    assert_not operation.request_payload.dig("values").key?("LLAMA_ARGS")
  end

  test "create rejects invalid definition" do
    assert_no_difference -> { LlamaServerOperation.count } do
      with_client(fake_client) do
        post llama_servers_path, params: { llama_server_definition: { server_id: "Bad ID", port: 99_999 } }
      end
    end

    assert_response :unprocessable_entity
  end

  test "edit loads current definition" do
    with_client(fake_client) do
      get edit_llama_server_path("main")
    end

    assert_response :success
    assert_select "input[name='llama_server_definition[server_id]'][readonly][value='main']"
    assert_select "input[name='llama_server_definition[ctx_size]'][value='8192']"
  end

  test "destroy refuses active server" do
    client = fake_client(active: true, enabled: true)

    assert_no_difference -> { LlamaServerOperation.count } do
      with_client(client) { delete llama_server_path("main") }
    end

    assert_redirected_to llama_servers_service_connections_path
    assert_match(/停止/, flash[:alert])
  end

  private

  def valid_params
    {
      llama_server_definition: {
        server_id: "new-model", source_type: "model", model: "/models/new.gguf",
        port: "10150", ctx_size: "8192", slots: "2"
      }
    }
  end

  def fake_client(active: false, enabled: false)
    Object.new.tap do |client|
      client.define_singleton_method(:list_servers) { [] }
      client.define_singleton_method(:list_models) { [] }
      client.define_singleton_method(:get_server) do |_id|
        {
          "server" => { "id" => "main", "active" => active, "enabled" => enabled },
          "values" => { "MODEL" => "/models/main.gguf", "PORT" => 10110, "CTX_SIZE" => 8192 }
        }
      end
    end
  end

  def with_client(client)
    original = LlamaSwitchdClient.method(:new)
    LlamaSwitchdClient.define_singleton_method(:new) { |**| client }
    yield
  ensure
    LlamaSwitchdClient.define_singleton_method(:new, original)
  end
end
