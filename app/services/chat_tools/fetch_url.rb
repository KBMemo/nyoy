# frozen_string_literal: true

module ChatTools
  class FetchUrl < RubyLLM::Tool
    description "指定 URL の HTML/テキスト本文を取得する。web_search の結果を深く読むときや、ユーザーが URL を共有したときに使う。PDF は取得できない。1回の応答で何度も繰り返さない。"

    def initialize(budget: nil)
      @budget = budget || WebToolBudget.from_settings
    end

    def name
      "fetch_url"
    end

    param :url, desc: "取得する http/https URL（PDF 不可）", required: true

    def execute(url:)
      if PdfUrl.blocked?(url)
        return { error: "PDF は現在取得対象外です。HTML のページを選んでください。" }
      end

      if (error = @budget.consume_fetch!)
        return error
      end

      Registry.url_fetcher.fetch(url)
    rescue SafeUrlFetcher::Error => e
      { error: e.message }
    end
  end
end
