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
    original = Rails.application.config.x.nyoy.openai_api_key
    service_connections(:openai).update!(api_token: "ui_token", enabled: true)
    Rails.application.config.x.nyoy.openai_api_key = nil

    ServiceConnectionSeeds.sync_from_env!

    record = service_connections(:openai).reload
    assert record.enabled?
    assert_equal "ui_token", record.api_token
  ensure
    Rails.application.config.x.nyoy.openai_api_key = original
  end

  test "sync_from_env updates api token when env provides one" do
    original = Rails.application.config.x.nyoy.openai_api_key
    service_connections(:openai).update!(api_token: "old_token", enabled: false)
    Rails.application.config.x.nyoy.openai_api_key = "env_token"

    ServiceConnectionSeeds.sync_from_env!

    record = service_connections(:openai).reload
    assert_equal "env_token", record.api_token
    assert_not record.enabled?
  ensure
    Rails.application.config.x.nyoy.openai_api_key = original
  end

  test "local compatibility token does not enable the OpenAI connection" do
    original = Rails.application.config.x.nyoy.openai_api_key
    Rails.application.config.x.nyoy.openai_api_key = "local"

    definition = ServiceConnectionSeeds.definitions.find { |item| item[:key] == "openai" }

    assert_nil definition[:api_token]
    assert_equal false, definition[:enabled]
  ensure
    Rails.application.config.x.nyoy.openai_api_key = original
  end

  test "gpt oss is enabled only with a dedicated server URL" do
    original = Rails.application.config.x.nyoy.gpt_oss_llama_cpp_url
    Rails.application.config.x.nyoy.gpt_oss_llama_cpp_url = nil
    definition = ServiceConnectionSeeds.definitions.find { |item| item[:key] == "gpt_oss" }
    assert_equal false, definition[:enabled]

    Rails.application.config.x.nyoy.gpt_oss_llama_cpp_url = "http://llama.test:10012"
    definition = ServiceConnectionSeeds.definitions.find { |item| item[:key] == "gpt_oss" }
    assert_equal true, definition[:enabled]
  ensure
    Rails.application.config.x.nyoy.gpt_oss_llama_cpp_url = original
  end
end
