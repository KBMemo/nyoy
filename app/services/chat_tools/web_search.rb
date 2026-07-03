# frozen_string_literal: true

module ChatTools
  class WebSearch < RubyLLM::Tool
    description "Web を検索して最新情報や参考 URL を探す。ニュース、技術情報、用語の確認などに使う。"

    def name
      "web_search"
    end

    param :q, desc: "検索クエリ", required: true
    param :limit, type: "integer", desc: "最大件数（省略時は接続設定の既定。最大 10）", required: false

    def execute(q:, limit: nil)
      client.search(q: q, limit: limit)
    rescue SearxngClient::Error => e
      { error: e.message }
    end

    private

    def client
      @client ||= Registry.searxng_client
    end
  end
end
