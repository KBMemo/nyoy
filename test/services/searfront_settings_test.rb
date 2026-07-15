# frozen_string_literal: true

require "test_helper"

class SearfrontSettingsTest < ActiveSupport::TestCase
  test "defaults include google for CAPTCHA resilience" do
    settings = SearfrontSettings.from(nil)

    assert_equal 5, settings.result_count
    assert_equal 1, settings.concurrent_searches
    assert_equal 1, settings.concurrent_fetches
    assert_equal "duckduckgo,google,wikipedia", settings.engines
    assert_equal 1, settings.retry_count
    assert_equal 2, settings.max_searches_per_turn
    assert_equal 3, settings.max_fetches_per_turn
  end

  test "clamps values to allowed ranges" do
    settings = SearfrontSettings.from(
      result_count: 99,
      concurrent_searches: 0,
      concurrent_fetches: 0,
      retry_count: -1,
      max_searches_per_turn: 99,
      max_fetches_per_turn: 0,
      engines: " duckduckgo , wikipedia , "
    )

    assert_equal 10, settings.result_count
    assert_equal 1, settings.concurrent_searches
    assert_equal 1, settings.concurrent_fetches
    assert_equal 0, settings.retry_count
    assert_equal 5, settings.max_searches_per_turn
    assert_equal 1, settings.max_fetches_per_turn
    assert_equal "duckduckgo,wikipedia", settings.engines
  end

  test "loads from searfront service connection" do
    service_connections(:searfront).update!(
      settings: {
        "result_count" => 3,
        "concurrent_searches" => 1,
        "engines" => "wikipedia",
        "retry_count" => 0
      }
    )

    settings = SearfrontSettings.load

    assert_equal 3, settings.result_count
    assert_equal "wikipedia", settings.engines
    assert_equal 0, settings.retry_count
  end
end
