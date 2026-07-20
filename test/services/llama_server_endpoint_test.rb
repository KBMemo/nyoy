# frozen_string_literal: true

require "test_helper"

class LlamaServerEndpointTest < ActiveSupport::TestCase
  test "builds a data plane URL from control scheme public host and server port" do
    url = LlamaServerEndpoint.build(
      control_url: "https://switchd.internal:11335/api?source=control",
      public_host: "llm-data.example.net",
      port: 10_010
    )

    assert_equal "https://llm-data.example.net:10010", url
  end

  test "supports an IPv6 public host" do
    url = LlamaServerEndpoint.build(control_url: "http://switchd:11335", public_host: "[2001:db8::10]", port: 10_010)

    assert_equal "http://[2001:db8::10]:10010", url
  end

  test "raises a typed error for an invalid port" do
    assert_raises(LlamaServerEndpoint::Error) do
      LlamaServerEndpoint.build(control_url: "http://switchd:11335", port: "invalid")
    end
  end
end
