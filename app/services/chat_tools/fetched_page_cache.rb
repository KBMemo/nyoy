# frozen_string_literal: true

require "digest"

module ChatTools
  module FetchedPageCache
    CACHE_PREFIX = "chat:fetched_page:"
    EXPIRES_IN = 30.minutes

    module_function

    def store(url:, title:, text:)
      page_id = Digest::SHA256.hexdigest(url.to_s)[0, 16]
      Rails.cache.write(
        cache_key(page_id),
        { url: url, title: title, text: text.to_s },
        expires_in: EXPIRES_IN
      )
      page_id
    end

    def read(page_id)
      Rails.cache.read(cache_key(page_id))
    end

    def cache_key(page_id)
      "#{CACHE_PREFIX}#{page_id}"
    end
  end
end
