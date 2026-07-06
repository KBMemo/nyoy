# frozen_string_literal: true

require "test_helper"

class ServiceConnectionOpenaiTest < ActiveSupport::TestCase
  test "requires api token when enabled" do
    connection = service_connections(:openai)
    connection.enabled = true
    connection.api_token = nil

    assert_not connection.valid?
    assert connection.errors[:api_token].any?
  end
end
