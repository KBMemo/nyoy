# frozen_string_literal: true

require "test_helper"

class LlamaServerRuntimeVerifierTest < ActiveSupport::TestCase
  test "returns a safe runtime snapshot when alias and slots match" do
    runtime = LlamaServerRuntimeProbe::Result.new(
      server_id: "main",
      model_alias: "main-alias",
      model_path: "/models/private/main.gguf",
      total_slots: 2
    )

    result = verifier(runtime).call(detail)

    assert_equal({ "model_alias" => "main-alias", "total_slots" => 2 }, result)
    assert_not result.key?("model_path")
  end

  test "rejects a runtime alias mismatch" do
    runtime = LlamaServerRuntimeProbe::Result.new(server_id: "main", model_alias: "other", total_slots: 2)

    error = assert_raises(LlamaServerRuntimeVerifier::Error) { verifier(runtime).call(detail) }

    assert_match "Runtime Aliasが不一致", error.message
  end

  test "rejects a slot count mismatch" do
    runtime = LlamaServerRuntimeProbe::Result.new(server_id: "main", model_alias: "main-alias", total_slots: 1)

    error = assert_raises(LlamaServerRuntimeVerifier::Error) { verifier(runtime).call(detail) }

    assert_match "slot数が不一致", error.message
  end

  test "reports a runtime probe error" do
    runtime = LlamaServerRuntimeProbe::Result.new(server_id: "main", error: "connection refused")

    error = assert_raises(LlamaServerRuntimeVerifier::Error) { verifier(runtime).call(detail) }

    assert_match "connection refused", error.message
  end

  private

  def verifier(runtime)
    probe = Object.new
    probe.define_singleton_method(:call) { |_servers| { "main" => runtime } }
    LlamaServerRuntimeVerifier.new(service_connections(:llama_switchd), probe: probe)
  end

  def detail
    {
      "server" => { "id" => "main", "alias" => "main-alias", "port" => 10_010, "ready" => true },
      "values" => { "SLOTS" => 2 }
    }
  end
end
