# frozen_string_literal: true

module ChatTools
  # Limits web_search / fetch_url usage within a single chat.complete turn.
  class WebToolBudget
    def self.from_settings(settings = SearxngSettings.load)
      new(
        max_searches: settings.max_searches_per_turn,
        max_fetches: settings.max_fetches_per_turn
      )
    end

    def initialize(max_searches:, max_fetches:)
      @max_searches = max_searches
      @max_fetches = max_fetches
      @searches = 0
      @fetches = 0
      @fetched_urls = {}
      @mutex = Mutex.new
    end

    attr_reader :max_searches, :max_fetches

    def consume_search!
      @mutex.synchronize do
        @searches += 1
        return nil if @searches <= @max_searches

        ToolResponse.limit_reached(
          tool: "web_search",
          code: "SEARCH_LIMIT_EXCEEDED",
          message: "web_search は1回の応答あたり最大 #{@max_searches} 回までです（#{@searches} 回目）。"
        )
      end
    end

    def consume_fetch!(url: nil)
      @mutex.synchronize do
        normalized_url = normalize_url(url)

        if normalized_url.present? && @fetched_urls.key?(normalized_url)
          return ToolResponse.error(
            tool: "fetch_url",
            code: "URL_ALREADY_FETCHED",
            retryable: false,
            url: normalized_url,
            message: "この URL は既に取得済みです。本文は再送しません。",
            next_action: "同じ URL を fetch_url で再取得せず、既に取得済みの情報で回答してください。"
          )
        end

        @fetches += 1

        if @fetches > @max_fetches
          return ToolResponse.limit_reached(
            tool: "fetch_url",
            code: "FETCH_LIMIT_EXCEEDED",
            url: normalized_url,
            message: "fetch_url は1回の応答あたり最大 #{@max_fetches} 回までです（#{@fetches} 回目）。"
          )
        end

        @fetched_urls[normalized_url] = true if normalized_url.present?
        nil
      end
    end

    private

    def normalize_url(url)
      uri = HttpUrl.parse(url)
      uri.fragment = nil
      uri.to_s
    rescue StandardError
      url.to_s.strip
    end
  end
end
