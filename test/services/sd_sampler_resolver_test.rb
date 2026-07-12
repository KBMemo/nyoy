# frozen_string_literal: true

require "test_helper"

class SdSamplerResolverTest < ActiveSupport::TestCase
  test "returns live samplers after switching model" do
    profile = sd_model_profiles(:pony)
    switcher = Object.new
    switcher.define_singleton_method(:switch) { |*| true }

    catalog = Object.new
    catalog.define_singleton_method(:names) { %w[euler_a dpmpp2m] }

    result = SdSamplerResolver.new(sd_model_profile: profile, switcher: switcher, catalog: catalog).resolve

    assert_equal %w[euler_a dpmpp2m], result[:samplers]
    assert_equal "euler_a", result[:default]
    assert_equal "live", result[:source]
  end

  test "falls back to family samplers when switch is unavailable" do
    profile = sd_model_profiles(:pony)
    switcher = Object.new
    switcher.define_singleton_method(:switch) { |*| false }

    catalog = Object.new
    catalog.define_singleton_method(:names) { [] }

    result = SdSamplerResolver.new(sd_model_profile: profile, switcher: switcher, catalog: catalog).resolve

    assert_equal profile.family_sampler_names, result[:samplers]
    assert_equal "family", result[:source]
  end
end
