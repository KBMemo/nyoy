# frozen_string_literal: true

require "test_helper"

class OpenaiChatModelsTest < ActiveSupport::TestCase
  test "filters chat-capable OpenAI model ids" do
    models = OpenaiChatModels.filter(
      %w[gpt-4o gpt-4o-mini whisper-1 dall-e-3 text-embedding-3-small o3-mini gpt-image-1]
    )

    assert_equal %w[gpt-4o gpt-4o-mini o3-mini], models
  end
end
