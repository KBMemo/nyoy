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
      @mutex = Mutex.new
    end

    attr_reader :max_searches, :max_fetches

    def consume_search!
      @mutex.synchronize do
        @searches += 1
        return nil if @searches <= @max_searches

        {
          error: "web_search は1回の応答あたり最大 #{@max_searches} 回までです（#{@searches} 回目）。既にある検索結果で回答してください。"
        }
      end
    end

    def consume_fetch!
      @mutex.synchronize do
        @fetches += 1
        return nil if @fetches <= @max_fetches

        {
          error: "fetch_url は1回の応答あたり最大 #{@max_fetches} 回までです（#{@fetches} 回目）。既に取得した本文で回答してください。"
        }
      end
    end
  end
end
