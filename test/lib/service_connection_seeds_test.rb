# frozen_string_literal: true

require "test_helper"

class ServiceConnectionSeedsTest < ActiveSupport::TestCase
  setup do
    NyoyConnectionStore.clear_cache!
  end

  test "seed preserves api token when definition has no token" do
    service_connections(:searxng).update!(api_token: "saved_token")

    ServiceConnectionSeeds.seed!

    assert_equal "saved_token", service_connections(:searxng).reload.api_token
  end

  test "seed overwrites api token when env provides token" do
    service_connections(:searxng).update!(api_token: "old_token")
    Rails.application.config.x.nyoy.searxng_api_token = "env_token"

    ServiceConnectionSeeds.seed!

    assert_equal "env_token", service_connections(:searxng).reload.api_token
  ensure
    Rails.application.config.x.nyoy.searxng_api_token = ENV["SEARXNG_API_TOKEN"]
  end

  test "seed_missing creates only missing builtin connections" do
    ServiceConnection.where(key: "readability").delete_all

    count = ServiceConnectionSeeds.seed_missing!

    assert_equal 1, count
    assert ServiceConnection.exists?(key: "readability")
  end

  test "seed_missing returns zero when all builtins exist" do
    ServiceConnectionSeeds.seed!

    assert_equal 0, ServiceConnectionSeeds.seed_missing!
  end
end
