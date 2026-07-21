# frozen_string_literal: true

require "test_helper"

class EmbeddingClientTest < ActiveSupport::TestCase
  test "extracts embedding vector from OpenAI-compatible response" do
    EmbeddingClient.define_method(:embed, ORIGINAL_EMBEDDING_CLIENT_EMBED)

    client = Class.new(EmbeddingClient) do
      define_method(:post_json) do |_path, _payload|
        { "data" => [ { "embedding" => [ 0.1, 0.2, 0.3 ] } ] }
      end
    end.new(base_url: "http://example.test", model: "test-model")

    assert_equal [ 0.1, 0.2, 0.3 ], client.embed(input: "hello")
  end

  test "raises when usage assignment is unavailable" do
    LlmUsageAssignment.where(usage_key: "embedding.memo_knowledge").delete_all

    error = assert_raises(EmbeddingClient::Error) { EmbeddingClient.new }

    assert_includes error.message, "embedding.memo_knowledge"
  end
end
