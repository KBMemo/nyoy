# frozen_string_literal: true

class PromptKnowledgeChunkEmbedder
  class Error < StandardError; end

  def initialize(client: EmbeddingClient.new)
    @client = client
  end

  def embed_text(text)
    vector = @client.embed(input: text.to_s.strip)
    validate_dimensions!(vector)
    vector
  rescue EmbeddingClient::Error => e
    raise Error, e.message
  end

  private

  def validate_dimensions!(vector)
    expected = Rails.application.config.x.nyoy.embedding_dimensions
    return if vector.length == expected

    raise Error, "expected #{expected} dimensions, got #{vector.length}"
  end
end
