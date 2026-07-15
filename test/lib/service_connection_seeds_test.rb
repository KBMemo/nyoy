# frozen_string_literal: true

require "test_helper"

class ServiceConnectionSeedsTest < ActiveSupport::TestCase
  setup do
    NyoyConnectionStore.clear_cache!
  end

  test "seed preserves api token when definition has no token" do
    service_connections(:searfront).update!(api_token: "saved_token")

    ServiceConnectionSeeds.seed!

    assert_equal "saved_token", service_connections(:searfront).reload.api_token
  end

  test "seed overwrites api token when env provides token" do
    service_connections(:searfront).update!(api_token: "old_token")
    Rails.application.config.x.nyoy.searfront_api_token = "env_token"

    ServiceConnectionSeeds.seed!

    assert_equal "env_token", service_connections(:searfront).reload.api_token
  ensure
    Rails.application.config.x.nyoy.searfront_api_token = ENV["SEARFRONT_TOKEN"]
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

  test "sync_from_env preserves enabled when env lacks token but DB has one" do
    service_connections(:openai).update!(api_token: "ui_token", enabled: true)
    Rails.application.config.x.nyoy.openai_api_key = nil

    ServiceConnectionSeeds.sync_from_env!

    record = service_connections(:openai).reload
    assert record.enabled?
    assert_equal "ui_token", record.api_token
  ensure
    Rails.application.config.x.nyoy.openai_api_key = ENV["OPENAI_API_KEY"]
  end

  test "sync_from_env updates api token when env provides one" do
    service_connections(:openai).update!(api_token: "old_token", enabled: false)
    Rails.application.config.x.nyoy.openai_api_key = "env_token"

    ServiceConnectionSeeds.sync_from_env!

    record = service_connections(:openai).reload
    assert_equal "env_token", record.api_token
    assert_not record.enabled?
  ensure
    Rails.application.config.x.nyoy.openai_api_key = ENV["OPENAI_API_KEY"]
  end
end
