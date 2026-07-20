# frozen_string_literal: true

require "test_helper"

class LlamaServerOperationTest < ActiveSupport::TestCase
  test "accepts lifecycle operation for switchd connection" do
    operation = LlamaServerOperation.new(
      service_connection: service_connections(:llama_switchd),
      managed_server_id: "main-model",
      action: "restart"
    )

    assert operation.valid?
  end

  test "rejects unsupported action and non switchd connection" do
    operation = LlamaServerOperation.new(
      service_connection: service_connections(:llama_cpp),
      managed_server_id: "main/model",
      action: "delete"
    )

    assert_not operation.valid?
    assert operation.errors[:action].any?
    assert operation.errors[:managed_server_id].any?
    assert operation.errors[:service_connection].any?
  end

  test "database prevents simultaneous operations for same server" do
    attributes = {
      service_connection: service_connections(:llama_switchd),
      managed_server_id: "main",
      action: "start"
    }
    LlamaServerOperation.create!(attributes)

    assert_raises(ActiveRecord::RecordNotUnique) do
      LlamaServerOperation.create!(attributes.merge(action: "stop"))
    end
  end
end
