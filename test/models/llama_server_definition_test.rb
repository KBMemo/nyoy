# frozen_string_literal: true

require "test_helper"

class LlamaServerDefinitionTest < ActiveSupport::TestCase
  test "normalizes typed local model values" do
    definition = LlamaServerDefinition.new(
      server_id: "main-model",
      source_type: "model",
      model: "/models/main.gguf",
      port: "10110",
      ctx_size: "8192",
      slots: "2",
      embedding: "0"
    )

    assert definition.valid?
    assert_equal 10_110, definition.values["PORT"]
    assert_equal 8192, definition.values["CTX_SIZE"]
    assert_equal false, definition.values["EMBEDDING"]
    assert_nil definition.values["HF_REPO"]
  end

  test "requires one selected source and valid port" do
    definition = LlamaServerDefinition.new(server_id: "Bad ID", source_type: "hf_repo", port: 70_000)

    assert_not definition.valid?
    assert definition.errors[:server_id].any?
    assert definition.errors[:hf_repo].any?
    assert definition.errors[:port].any?
  end

  test "builds form values from API definition" do
    definition = LlamaServerDefinition.from_api(
      server_id: "main",
      values: { "HF_REPO" => "org/main:Q4", "PORT" => 10110, "SLOTS" => 2 }
    )

    assert_equal "hf_repo", definition.source_type
    assert_equal "org/main:Q4", definition.hf_repo
    assert_equal 2, definition.slots
  end
end
