# frozen_string_literal: true

module ChatTools
  class SearchFetchedPage < RubyLLM::Tool
    WINDOW = 700
    MAX_MATCHES = 4
    TERM_PATTERN = /[[:word:]ー\p{Han}\p{Hiragana}\p{Katakana}]+/u

    description <<~DESC.squish
      fetch_url で取得済みの長いページを検索する。
      page_id と query を指定すると、該当箇所の短い抜粋だけ返す。
      長いページを読み足す場合は fetch_url を再実行せず、このツールを使う。
    DESC

    def name
      "search_fetched_page"
    end

    param :page_id, desc: "fetch_url が返した page_id", required: true
    param :query, desc: "ページ内で探す語句・内容", required: true

    def execute(page_id:, query:)
      page = FetchedPageCache.read(page_id)

      unless page
        return ToolResponse.error(
          tool: "search_fetched_page",
          code: "PAGE_NOT_FOUND",
          retryable: false,
          message: "取得済みページのキャッシュが見つかりません。",
          next_action: "fetch_url を何度も繰り返さず、必要ならユーザーに URL 再指定を依頼してください。"
        )
      end

      matches = find_matches(page[:text].to_s, query.to_s)

      ToolResponse.preview(
        ok: true,
        tool: "search_fetched_page",
        page_id: page_id,
        url: page[:url],
        title: page[:title],
        query: query,
        matches: matches,
        next_action: "この抜粋を使って回答してください。"
      )
    end

    private

    def find_matches(text, query)
      terms = query.scan(TERM_PATTERN).uniq
      return [] if terms.empty?

      positions = terms.flat_map do |term|
        text.enum_for(:scan, Regexp.new(Regexp.escape(term), Regexp::IGNORECASE)).map do
          Regexp.last_match.begin(0)
        end
      end.uniq.sort

      positions = distinct_excerpt_positions(positions).first(MAX_MATCHES)

      positions.map do |pos|
        start_pos = [ pos - WINDOW, 0 ].max
        {
          offset: start_pos,
          excerpt: text[start_pos, WINDOW * 2]
        }
      end
    end

    def distinct_excerpt_positions(positions)
      positions.each_with_object([]) do |position, distinct|
        next if distinct.last && position - distinct.last < WINDOW * 2

        distinct << position
      end
    end
  end
end
