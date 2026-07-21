# frozen_string_literal: true

require "test_helper"

class ChatModelSeedsTest < ActiveSupport::TestCase
  test "seed registers configured local chat models" do
    ChatModelCatalog.seed!

    gemma = Model.find_by!(provider: "openai", model_id: "gemma-4-e4b-it-qat-ud-q4-k-xl")
    gpt_oss = Model.find_by!(provider: "openai", model_id: "gpt-oss")

    assert_equal "gemma-4-e4b-it-qat-ud-q4-k-xl", gemma.name
    assert_equal "gpt-oss", gpt_oss.name
    assert_equal service_connections(:llama_cpp), gemma.service_connection
    assert_equal service_connections(:gpt_oss), gpt_oss.service_connection
  end

  test "seed preserves specialized model capabilities and modalities" do
    vision = Model.find_by!(provider: "openai", model_id: service_connections(:vision_llama).server_model)
    vision.update!(
      capabilities: [ "chat", "vision-specialized" ],
      modalities: { "input" => %w[text image], "output" => [ "text" ] }
    )

    ChatModelCatalog.seed!

    vision.reload
    assert_includes vision.capabilities, "vision-specialized"
    assert_includes vision.modalities.fetch("input"), "image"
  end
end
