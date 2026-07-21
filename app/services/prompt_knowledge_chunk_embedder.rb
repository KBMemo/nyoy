# frozen_string_literal: true

class PromptKnowledgeChunkEmbedder
  class Error < StandardError; end

  def initialize(client: EmbeddingClient.new(usage_key: "embedding.prompt_knowledge"))
    @client = client
  end

  def embed_text(text)
    input = EmbeddingInput.truncate(text)
    if EmbeddingInput.truncated?(text)
      Rails.logger.warn(
        "Embedding input truncated to #{input.length} chars " \
        "(EMBEDDING_MAX_CHARS=#{Rails.application.config.x.nyoy.embedding_max_chars})"
      )
    end

    vector = @client.embed(input: input)
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
