# frozen_string_literal: true

require "test_helper"

class NyoyConnectionStoreTest < ActiveSupport::TestCase
  setup do
    NyoyConnectionStore.clear_cache!
  end

  test "reads url and model from service connection" do
    assert_equal "http://balvenie:10010", NyoyConnectionStore.url(:llama_cpp)
    assert_equal "gemma-4-e4b-it-qat-ud-q4-k-xl", NyoyConnectionStore.server_model(:llama_cpp)
  end

  test "does not fall back to environment defaults when llm connection is missing" do
    ServiceConnection.delete_all
    NyoyConnectionStore.clear_cache!

    assert_nil NyoyConnectionStore.url(:llama_cpp)
    assert_nil NyoyConnectionStore.server_model(:llama_cpp)
    assert_not NyoyConnectionStore.enabled?(:llama_cpp)
  end

  test "does not fall back to environment defaults when llm connection is disabled" do
    service_connections(:llama_cpp).update!(enabled: false)

    assert_nil NyoyConnectionStore.url(:llama_cpp)
    assert_nil NyoyConnectionStore.server_model(:llama_cpp)
    assert_not NyoyConnectionStore.enabled?(:llama_cpp)
  end

  test "keeps environment fallback for non-llm connections" do
    ServiceConnection.where(key: "readability").delete_all

    assert_equal Rails.application.config.x.nyoy.readability_url, NyoyConnectionStore.url(:readability)
    assert NyoyConnectionStore.enabled?(:readability)
  end

  test "reads updated url without explicit cache clear" do
    service_connections(:gpt_oss).update!(base_url: "http://updated-gpt-oss:10012")

    assert_equal "http://updated-gpt-oss:10012", NyoyConnectionStore.url(:gpt_oss)
  end
end
