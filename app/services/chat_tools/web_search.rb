# frozen_string_literal: true

module ChatTools
  class WebSearch < RubyLLM::Tool
    description "Web を検索して最新情報や参考 URL を探す。ニュース、技術情報、用語の確認などに使う。"

    def name
      "web_search"
    end

    param :q, desc: "検索クエリ", required: true
    param :limit, type: "integer", desc: "最大件数（既定 10、最大 20）", required: false

    def execute(q:, limit: 10)
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
