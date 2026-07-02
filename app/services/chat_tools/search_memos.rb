# frozen_string_literal: true

module ChatTools
  class SearchMemos < RubyLLM::Tool
    description "徒然（tsuredure）に保存されたメモをキーワード検索する。旅行や技術メモなど過去の記録を探すときに使う。"

    def name
      "search_memos"
    end

    param :q, desc: "検索キーワード", required: true
    param :limit, type: "integer", desc: "最大件数（既定 10、最大 50）", required: false

    def execute(q:, limit: 10)
      response = client.list_memos(
        q: q,
        limit: clamp_limit(limit),
        fields: "uid,title,snippet,updated_at,draft,url,tags"
      )
      { memos: response.fetch("memos", []) }
    rescue TsurezureClient::Error => e
      { error: e.message }
    end

    private

    def client
      @client ||= Registry.client
    end

    def clamp_limit(limit)
      value = limit.to_i
      value = 10 if value <= 0
      [value, 50].min
    end
  end
end
