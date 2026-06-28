# frozen_string_literal: true

class PromptSkillDraftStore
  CACHE_PREFIX = "prompt_skill_draft"
  TTL = 1.hour

  class << self
    def write(draft)
      token = SecureRandom.urlsafe_base64(32)
      Rails.cache.write(cache_key(token), normalize(draft), expires_in: TTL)
      token
    end

    def fetch(token)
      return nil if token.blank?

      draft = Rails.cache.read(cache_key(token))
      Rails.cache.delete(cache_key(token)) if draft
      draft
    end

    private

    def normalize(draft)
      draft.stringify_keys.slice("name", "body", "default_negative_prompt", "source_chunk_ids")
    end

    def cache_key(token)
      "#{CACHE_PREFIX}:#{token}"
    end
  end
end
