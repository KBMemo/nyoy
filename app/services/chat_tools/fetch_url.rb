# frozen_string_literal: true

module ChatTools
  class FetchUrl < RubyLLM::Tool
    description "指定 URL のページ本文を取得する。web_search の結果を深く読むときや、ユーザーが URL を共有したときに使う。"

    def name
      "fetch_url"
    end

    param :url, desc: "取得する http/https URL", required: true

    def execute(url:)
      Registry.url_fetcher.fetch(url)
    rescue SafeUrlFetcher::Error => e
      { error: e.message }
    end
  end
end
