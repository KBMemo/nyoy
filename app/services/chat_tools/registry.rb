# frozen_string_literal: true

module ChatTools
  module Registry
    MEMO_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      徒然（tsuredure）メモツールが利用可能です。
      関連メモの抜粋は自動で参照コンテキストに含まれます。
      さらに探すときは search_memos、本文が必要なときは get_memo を使ってください。
      create_memo はユーザーが明示的に保存を求めたときだけ使ってください。
      update_memo では必ず get_memo で取得した updated_at を渡してください。
      メモ本文は AsciiDoc 形式です。
    TEXT

    WEB_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      web_search で Web 検索、fetch_url でページ本文を取得できます。
      最新情報が必要なときは web_search を使い、詳細が必要なら fetch_url で本文を読んでください。
      fetch_url は公開 Web の http/https URL のみ取得できます。
    TEXT

    FETCH_URL_INSTRUCTIONS = <<~TEXT.squish
      fetch_url で公開 Web ページの本文を取得できます。http/https URL のみ対応です。
      HTML ページは readability-js-server で本文抽出します。
    TEXT

    MEMO_TOOL_CLASSES = [
      SearchMemos,
      GetMemo,
      CreateMemo,
      UpdateMemo
    ].freeze

    WEB_TOOL_CLASSES = [
      WebSearch,
      FetchUrl
    ].freeze

    module_function

    def available?
      tool_classes.any?
    end

    def memo_tools_available?
      NyoyConnectionStore.enabled?(:kbmemo) && NyoyConnectionStore.api_token(:kbmemo).present?
    end

    def web_tools_available?
      NyoyConnectionStore.enabled?(:searxng) && NyoyConnectionStore.url(:searxng).present?
    end

    def tool_classes
      classes = []
      classes.concat(MEMO_TOOL_CLASSES) if memo_tools_available?
      classes << WebSearch if web_tools_available?
      classes << FetchUrl
      classes
    end

    def apply!(llm_chat)
      tools = tool_classes
      return llm_chat if tools.empty?

      instructions = []
      instructions << MEMO_TOOLS_INSTRUCTIONS if memo_tools_available?
      if web_tools_available?
        instructions << WEB_TOOLS_INSTRUCTIONS
      elsif tools.include?(FetchUrl)
        instructions << FETCH_URL_INSTRUCTIONS
      end

      llm_chat.with_tools(*tools.map(&:new))
              .with_instructions(instructions.join(" "), append: true)
    end

    def client
      TsurezureClient.new
    end

    def searxng_client
      SearxngClient.new
    end

    def url_fetcher
      SafeUrlFetcher.new(readability_client: readability_client)
    end

    def readability_client
      ReadabilityClient.new
    end

    def reset_client!
    end
  end
end
