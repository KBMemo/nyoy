# frozen_string_literal: true

require "test_helper"

class LlamaServerRuntimeProbeTest < ActiveSupport::TestCase
  test "probes only ready servers through control host and data port" do
    urls = []
    factory = lambda do |base_url|
      urls << base_url
      Object.new.tap do |client|
        client.define_singleton_method(:props) do
          { "model_alias" => "main", "model_path" => "/models/main.gguf", "total_slots" => 2 }
        end
      end
    end
    probe = LlamaServerRuntimeProbe.new(control_url: "http://balvenie:11335", client_factory: factory)

    result = probe.call([
      { "id" => "main", "port" => 10010, "ready" => true },
      { "id" => "stopped", "port" => 10011, "ready" => false }
    ])

    assert_equal [ "http://balvenie:10010" ], urls
    assert_equal "main", result["main"].model_alias
    assert_equal 2, result["main"].total_slots
    assert_not result.key?("stopped")
  end

  test "isolates per server errors" do
    factory = lambda do |_base_url|
      Object.new.tap do |client|
        client.define_singleton_method(:props) { raise LlamaCppClient::Error, "down" }
      end
    end
    probe = LlamaServerRuntimeProbe.new(control_url: "http://balvenie:11335", client_factory: factory)

    result = probe.call([ { "id" => "main", "port" => 10010, "ready" => true } ])

    assert_equal "down", result["main"].error
  end

  test "probes through the configured public host" do
    urls = []
    factory = lambda do |base_url|
      urls << base_url
      Object.new.tap { |client| client.define_singleton_method(:props) { {} } }
    end
    probe = LlamaServerRuntimeProbe.new(
      control_url: "https://switchd.internal:11335/control",
      public_host: "llm-data.example.net",
      client_factory: factory
    )

    probe.call([ { "id" => "main", "port" => 10010, "ready" => true } ])

    assert_equal [ "https://llm-data.example.net:10010" ], urls
  end
end
