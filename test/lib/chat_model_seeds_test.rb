# frozen_string_literal: true

require "test_helper"

class ChatModelSeedsTest < ActiveSupport::TestCase
  test "seed registers configured local chat models" do
    ChatModelCatalog.seed!

    gemma = Model.find_by!(provider: "openai", model_id: "gemma-4-12b-it-vision-mtp")
    gpt_oss = Model.find_by!(provider: "openai", model_id: "gpt-oss")

    assert_equal "Gemma Vision", gemma.name
    assert_equal "GPT-OSS", gpt_oss.name
    assert_equal "llama_cpp", gemma.metadata["connection_key"]
    assert_equal "gpt_oss", gpt_oss.metadata["connection_key"]
  end
end
