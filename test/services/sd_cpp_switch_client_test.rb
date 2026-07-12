# frozen_string_literal: true

require "test_helper"

class SdCppSwitchClientTest < ActiveSupport::TestCase
  test "raises switchd error when response body is not json" do
    client = SdCppSwitchClient.new(base_url: "http://switch.test", token: "secret")
    response = build_response(code: "200", body: "Failed to connect to sd-server")

    with_http_stub(response) do
      error = assert_raises(SdCppSwitchClient::Error) { client.switch("pony-v6") }
      assert_equal "Failed to connect to sd-server", error.message
    end
  end

  test "raises switchd error when response reports failure" do
    client = SdCppSwitchClient.new(base_url: "http://switch.test", token: "secret")
    response = build_response(code: "500", body: { ok: false, error: "model load failed" }.to_json)

    with_http_stub(response) do
      error = assert_raises(SdCppSwitchClient::Error) { client.switch("pony-v6") }
      assert_equal "model load failed", error.message
    end
  end

  private

  def build_response(code:, body:)
    klass = code.to_i >= 400 ? Net::HTTPInternalServerError : Net::HTTPOK
    klass.new("1.1", code, "OK").tap do |response|
      response.instance_variable_set(:@body, body)
      response.instance_variable_set(:@read, true)
    end
  end

  def with_http_stub(response)
    http = Object.new
    http.define_singleton_method(:request) { |_req| response }
    http.define_singleton_method(:open_timeout=) { |_value| nil }
    http.define_singleton_method(:read_timeout=) { |_value| nil }

    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_args| http }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end
end
