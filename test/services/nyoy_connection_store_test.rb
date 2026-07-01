# frozen_string_literal: true

require "test_helper"

class NyoyConnectionStoreTest < ActiveSupport::TestCase
  setup do
    NyoyConnectionStore.clear_cache!
  end

  test "reads url and model from service connection" do
    assert_equal "http://balvenie:10010", NyoyConnectionStore.url(:llama_cpp)
    assert_equal "gemma-4-12b-it-vision-mtp", NyoyConnectionStore.server_model(:llama_cpp)
  end

  test "falls back to environment defaults when connection missing" do
    ServiceConnection.delete_all
    NyoyConnectionStore.clear_cache!

    assert_equal Rails.application.config.x.nyoy.llama_cpp_url, NyoyConnectionStore.url(:llama_cpp)
    assert_equal Rails.application.config.x.nyoy.llama_model, NyoyConnectionStore.server_model(:llama_cpp)
  end
end
