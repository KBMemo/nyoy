# frozen_string_literal: true

module ChatTools
  class WebSearch < RubyLLM::Tool
    description "Web を検索して最新情報や参考 URL を探す。ニュース、技術情報、用語の確認などに使う。1回の応答で何度も繰り返さない。"

    def initialize(budget: nil)
      @budget = budget || WebToolBudget.from_settings
    end

    def name
      "web_search"
    end

    param :q, desc: "検索クエリ", required: true
    param :limit, type: "integer", desc: "最大件数（省略時は接続設定の既定。最大 10）", required: false

    def execute(q:, limit: nil)
      if (error = @budget.consume_search!)
        return error
      end

      payload = client.search(q: q, limit: limit)
      filter_pdf_results(payload)
    rescue SearxngClient::Error => e
      ToolResponse.error(tool: "web_search", message: e.message)
    end

    private

    def filter_pdf_results(payload)
      results = Array(payload["results"])
      kept = []
      skipped = []

      results.each do |result|
        url = result.is_a?(Hash) ? result["url"].to_s : ""
        if PdfUrl.blocked?(url)
          skipped << url
        else
          kept << result
        end
      end

      payload.merge(
        "results" => kept,
        "number_of_results" => kept.size,
        "skipped_pdf_urls" => skipped.presence
      ).compact
    end

    def client
      @client ||= Registry.searxng_client
    end
  end
end
