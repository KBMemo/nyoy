# frozen_string_literal: true

require "test_helper"

class LlamaServerOperationJobTest < ActiveJob::TestCase
  test "runs action and stores safe status snapshot" do
    operation = create_operation(action: "restart")
    client = Object.new
    client.define_singleton_method(:restart_server) { |id| raise unless id == "main" }
    client.define_singleton_method(:get_server) do |_id|
      {
        "server" => {
          "id" => "main", "alias" => "main-alias", "port" => 10010,
          "state" => "ready", "ready" => true,
          "systemd" => { "stdout" => "must not persist" }
        },
        "values" => { "SLOTS" => 2 }
      }
    end

    with_runtime_verifier({ "model_alias" => "main-alias", "total_slots" => 2 }) do
      with_client(client) { LlamaServerOperationJob.perform_now(operation.id) }
    end

    operation.reload
    assert_equal "succeeded", operation.status
    assert operation.started_at
    assert operation.finished_at
    assert_equal "ready", operation.response_snapshot["state"]
    assert_equal 2, operation.response_snapshot.dig("runtime", "total_slots")
    assert_not operation.response_snapshot.key?("systemd")
  end

  test "records client failure" do
    operation = create_operation(action: "start")
    client = Object.new
    client.define_singleton_method(:start_server) { |_id| raise LlamaSwitchdClient::Error, "start failed" }

    with_client(client) { LlamaServerOperationJob.perform_now(operation.id) }

    operation.reload
    assert_equal "failed", operation.status
    assert_equal "start failed", operation.error_message
    assert operation.finished_at
  end

  test "creates definition and stores resulting status" do
    operation = LlamaServerOperation.create!(
      service_connection: service_connections(:llama_switchd),
      managed_server_id: "new-model",
      action: "create",
      request_payload: { "values" => { "MODEL" => "/models/new.gguf", "PORT" => 10150 } }
    )
    client = Object.new
    client.define_singleton_method(:create_server) { |id:, values:| raise unless id == "new-model" && values["PORT"] == 10150 }
    client.define_singleton_method(:get_server) { |_id| { "server" => { "id" => "new-model", "state" => "stopped" } } }

    with_client(client) { LlamaServerOperationJob.perform_now(operation.id) }

    assert_equal "succeeded", operation.reload.status
    assert_equal "stopped", operation.response_snapshot["state"]
  end

  test "records runtime verification failure while preserving server snapshot" do
    operation = create_operation(action: "restart")
    client = Object.new
    client.define_singleton_method(:restart_server) { |_id| }
    client.define_singleton_method(:get_server) do |_id|
      { "server" => { "id" => "main", "alias" => "main-alias", "port" => 10010, "state" => "ready", "ready" => true } }
    end
    verifier = Object.new
    verifier.define_singleton_method(:call) { |_| raise LlamaServerRuntimeVerifier::Error, "Runtime Aliasが不一致です" }

    with_runtime_verifier(verifier) do
      with_client(client) { LlamaServerOperationJob.perform_now(operation.id) }
    end

    operation.reload
    assert_equal "failed", operation.status
    assert_match "Runtime Aliasが不一致", operation.error_message
    assert_equal "ready", operation.response_snapshot["state"]
  end

  private

  def create_operation(action:)
    LlamaServerOperation.create!(
      service_connection: service_connections(:llama_switchd),
      managed_server_id: "main",
      action: action
    )
  end

  def with_client(client)
    original = LlamaSwitchdClient.method(:new)
    LlamaSwitchdClient.define_singleton_method(:new) { |**| client }
    yield
  ensure
    LlamaSwitchdClient.define_singleton_method(:new, original)
  end

  def with_runtime_verifier(result_or_verifier)
    verifier = if result_or_verifier.respond_to?(:call)
      result_or_verifier
    else
      Object.new.tap { |object| object.define_singleton_method(:call) { |_| result_or_verifier } }
    end
    original = LlamaServerRuntimeVerifier.method(:new)
    LlamaServerRuntimeVerifier.define_singleton_method(:new) { |*| verifier }
    yield
  ensure
    LlamaServerRuntimeVerifier.define_singleton_method(:new, original)
  end
end
