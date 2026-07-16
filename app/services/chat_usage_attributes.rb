# frozen_string_literal: true

class ChatUsageAttributes
  class << self
    def from(source)
      usage = usage_hash(source)
      return {} if usage.blank?

      details = hash_at(usage, "prompt_tokens_details", :prompt_tokens_details)
      {
        input_tokens: integer_at(usage, "prompt_tokens", :prompt_tokens, "input_tokens", :input_tokens),
        output_tokens: integer_at(usage, "completion_tokens", :completion_tokens, "output_tokens", :output_tokens),
        cached_tokens: integer_at(details, "cached_tokens", :cached_tokens),
        cache_creation_tokens: integer_at(details, "cache_creation_tokens", :cache_creation_tokens)
      }.compact
    end

    private

    def usage_hash(source)
      if source.is_a?(Hash)
        nested = hash_at(source, "usage", :usage)
        return nested if nested.present?

        return source
      end

      if source.respond_to?(:usage)
        usage = source.usage
        return usage if usage.is_a?(Hash)
      end

      raw = source.respond_to?(:raw) ? source.raw : nil
      raw = raw.to_h if raw.respond_to?(:to_h)
      return {} unless raw.is_a?(Hash)

      hash_at(raw, "usage", :usage) || {}
    end

    def hash_at(hash, *keys)
      keys.each do |key|
        value = hash[key] if hash.respond_to?(:key?) && hash.key?(key)
        return value if value.is_a?(Hash)
      end
      {}
    end

    def integer_at(hash, *keys)
      keys.each do |key|
        next unless hash.respond_to?(:key?) && hash.key?(key)

        value = Integer(hash[key])
        return value if value >= 0
      rescue ArgumentError, TypeError
        next
      end
      nil
    end
  end
end
