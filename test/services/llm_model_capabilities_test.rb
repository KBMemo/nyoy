# frozen_string_literal: true

require "test_helper"

class LlmModelCapabilitiesTest < ActiveSupport::TestCase
  test "normalizes current model metadata" do
    model = Model.new(
      capabilities: [ "chat", "embedding" ],
      modalities: { "input" => %w[text image] }
    )

    assert_equal %i[text_generation tool_calling vision embedding], LlmModelCapabilities.for(model)
  end

  test "does not infer capabilities from model name" do
    model = Model.new(model_id: "vision-embedding-model", capabilities: [], modalities: {})

    assert_empty LlmModelCapabilities.for(model)
  end
end
