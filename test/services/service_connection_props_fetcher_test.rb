# frozen_string_literal: true

require "test_helper"

class ServiceConnectionPropsFetcherTest < ActiveSupport::TestCase
  test "maps props into sampling params" do
    connection = service_connections(:llama_cpp)
    fetcher = ServiceConnectionPropsFetcher.new(connection)
    fetcher.define_singleton_method(:fetch_props) do
      {
        "default_generation_settings" => {
          "params" => {
            "temperature" => 0.7,
            "top_p" => 0.8,
            "top_k" => 20,
            "n_predict" => 1024
          }
        }
      }
    end

    result = fetcher.call

    assert result.ok
    assert_in_delta 0.7, result.sampling.temperature
    assert_in_delta 0.8, result.sampling.top_p
    assert_equal 20, result.sampling.top_k
    assert_equal 1024, result.sampling.max_tokens
  end

  test "rejects non chat backends" do
    result = ServiceConnectionPropsFetcher.new(service_connections(:searfront)).call

    assert_not result.ok
    assert_match(/対応していません/, result.message)
  end
end
