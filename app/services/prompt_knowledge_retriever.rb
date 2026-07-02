# frozen_string_literal: true

class PromptKnowledgeRetriever
  DEFAULT_LIMIT = 10

  def initialize(client: EmbeddingClient.new, limit: DEFAULT_LIMIT)
    @client = client
    @limit = limit
  end

  def retrieve(query)
    text = query.to_s.strip
    return PromptKnowledgeChunk.none if text.blank?

    vector = @client.embed(input: text)
    PromptKnowledgeChunk.from_prompt.embedded.nearest_neighbors(:embedding, vector, distance: "cosine").limit(@limit)
  rescue EmbeddingClient::Error
    PromptKnowledgeChunk.none
  end
end
