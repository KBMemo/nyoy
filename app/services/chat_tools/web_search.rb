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
      annotate_empty_results(filter_pdf_results(payload))
    rescue SearfrontClient::Error, SearxngClient::Error => e
      ToolResponse.error(tool: "web_search", message: e.message)
    end

    private

    def annotate_empty_results(payload)
      return payload if Array(payload["results"]).any?

      reasons = Array(payload["unresponsive_engines"]).filter_map do |entry|
        next unless entry.is_a?(Array)

        "#{entry[0]}: #{entry[1]}"
      end
      gateway_warnings = Array(payload["warnings"]).map(&:to_s).reject(&:blank?)
      warning =
        if reasons.any?
          "検索結果が空です（#{reasons.join(', ')}）。別エンジンで再試行済みの場合があります。"
        elsif gateway_warnings.any?
          "検索結果が空です（#{gateway_warnings.join(', ')}）。"
        else
          tried = Array(payload["engines_tried"]).presence&.join(" → ")
          if tried
            "検索結果が空です（試行: #{tried}）。接続設定を確認してください。"
          else
            "検索結果が空です。別のクエリか、searfront 接続設定を確認してください。"
          end
        end

      payload.merge("warning" => warning)
    end

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
      @client ||= Registry.web_search_client
    end
  end
end
