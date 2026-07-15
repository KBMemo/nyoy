# frozen_string_literal: true

module ChatTools
  # Limits web_search / fetch_url usage within a single chat.complete turn.
  class WebToolBudget
    def self.from_settings(settings = SearfrontSettings.load)
      new(
        max_searches: settings.max_searches_per_turn,
        max_fetches: settings.max_fetches_per_turn
      )
    end

    # Restore a budget snapshot used by AgentGraph research nodes.
    def self.from_graph_budget(budget)
      budget = (budget || {}).stringify_keys
      settings = SearfrontSettings.load
      new(
        max_searches: positive(budget["max_searches"], settings.max_searches_per_turn),
        max_fetches: positive(budget["max_fetches"], settings.max_fetches_per_turn),
        searches: budget["searches_used"].to_i,
        fetches: budget["fetches_used"].to_i,
        fetched_urls: Array(budget["fetched_urls"])
      )
    end

    def self.positive(value, fallback)
      n = value.to_i
      n.positive? ? n : fallback
    end
    private_class_method :positive

    def initialize(max_searches:, max_fetches:, searches: 0, fetches: 0, fetched_urls: [])
      @max_searches = max_searches
      @max_fetches = max_fetches
      @searches = searches.to_i
      @fetches = fetches.to_i
      @fetched_urls = {}
      Array(fetched_urls).each do |url|
        key = normalize_url(url)
        @fetched_urls[key] = true if key.present?
      end
      @mutex = Mutex.new
    end

    attr_reader :max_searches, :max_fetches, :searches, :fetches

    def to_graph_budget
      {
        "searches_used" => @searches,
        "fetches_used" => @fetches,
        "max_searches" => @max_searches,
        "max_fetches" => @max_fetches,
        "fetched_urls" => @fetched_urls.keys
      }
    end

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
