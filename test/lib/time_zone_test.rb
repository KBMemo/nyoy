# frozen_string_literal: true

require "test_helper"

class TimeZoneTest < ActiveSupport::TestCase
  test "application time zone is Tokyo" do
    assert_equal "Tokyo", Time.zone.name
  end

  test "localize uses Tokyo for stored utc timestamps" do
    time = Time.utc(2026, 7, 3, 8, 56, 0)
    formatted = I18n.l(time.in_time_zone, format: :short)

    assert_equal "2026/07/03 17:56", formatted
  end
end
