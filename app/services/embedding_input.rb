# frozen_string_literal: true

class EmbeddingInput
  def self.truncate(text)
    normalized = text.to_s.strip
    max_chars = Rails.application.config.x.nyoy.embedding_max_chars
    return normalized if normalized.length <= max_chars

    normalized[0, max_chars]
  end

  def self.truncated?(text)
    truncate(text) != text.to_s.strip
  end
end
