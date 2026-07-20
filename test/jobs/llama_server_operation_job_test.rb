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
          "id" => "main", "state" => "ready", "ready" => true,
          "systemd" => { "stdout" => "must not persist" }
        }
      }
    end

    with_client(client) { LlamaServerOperationJob.perform_now(operation.id) }

    operation.reload
    assert_equal "succeeded", operation.status
    assert operation.started_at
    assert operation.finished_at
    assert_equal "ready", operation.response_snapshot["state"]
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
end
