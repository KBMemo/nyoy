# frozen_string_literal: true

module ChatTools
  module Registry
    MEMO_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      徒然（tsuredure）メモツールが利用可能です。
      関連メモの抜粋は自動で参照コンテキストに含まれます。
      さらに探すときは search_memos、本文が必要なときは get_memo を使ってください。
      create_memo はユーザーが明示的に保存を求めたときだけ使ってください。
      update_memo では必ず get_memo で取得した updated_at を渡してください。
      create_memo / update_memo の body は Markdown で書いてください（徒然側で AsciiDoc に変換）。
      Chat に葛籠へアーカイブ済みの添付画像がある場合、image::media: マクロは自動で本文末尾に挿入されます（手書き不要）。
      get_memo で読む本文は AsciiDoc ですが、そのまま理解して Markdown で更新してください。
    TEXT

    TOOL_ORCHESTRATION_INSTRUCTIONS = <<~TEXT.squish
      ツールは必要なときだけ使う。ユーザーの質問を読んでから選ぶ。
      最新の事実・ニュース・Web 上の情報 → web_search（詳細は fetch_url）。
      過去の自分のメモ → search_memos / get_memo（自動注入の RAG 抜粋で足りないとき）。
      添付画像の視覚的内容（写っているもの・文字・見た目）→ analyze_image。
      画像が添付されていても、質問がテキストだけで答えられるなら analyze_image は使わない。
      複数のツールが必要なら順序よく組み合わせてよい。
    TEXT

    WEB_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      web_search（SearXNG）で Web 検索、fetch_url でページ本文を取得できます。
      最新情報が必要なときは web_search を使い、詳細が必要なら fetch_url で本文を読んでください。
      fetch_url は公開 Web の http/https URL のみ取得できます。
    TEXT

    FETCH_URL_INSTRUCTIONS = <<~TEXT.squish
      fetch_url で公開 Web ページの本文を取得できます。http/https URL のみ対応です。
      HTML ページは readability-js-server で本文抽出します。
    TEXT

    VISION_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      analyze_image は vision LLM で画像を解析する。添付画像または tsuzura_media_id を指定できる。
      画像の説明・OCR・「何が写っているか」など視覚情報が回答に不可欠なときだけ使う。
      メッセージ本文だけで足りる場合、Web 検索で足りる場合、添付が無関係な場合は使わない。
      使うときは prompt に具体的な質問を渡す。
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

    VISION_TOOL_CLASSES = [
      AnalyzeImage
    ].freeze

    MEDIA_TOOL_CLASSES = [
      ListAlbums,
      GetMedia
    ].freeze

    MEDIA_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      list_albums / get_media で葛籠（tsuzura）に保存されたメディアを参照できます。
      Bearer 認証で GET /v1/media/:id/file からバイナリ取得可能です（如意は TsuzuraClient#download_media）。
      Chat に添付した画像は「Nyoy Chat」アルバムへ自動アーカイブされ、メタデータに tsuzura_media_id が付きます。
      create_memo / update_memo 実行時に image::media: マクロが自動挿入されます。
    TEXT

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

    def vision_tools_available?
      NyoyConnectionStore.enabled?(:vision_llama) && NyoyConnectionStore.url(:vision_llama).present?
    end

    def media_tools_available?
      NyoyConnectionStore.enabled?(:tsuzura) && NyoyConnectionStore.api_token(:tsuzura).present?
    end

    def tool_classes
      classes = []
      classes.concat(MEMO_TOOL_CLASSES) if memo_tools_available?
      classes << WebSearch if web_tools_available?
      classes << FetchUrl
      classes.concat(VISION_TOOL_CLASSES) if vision_tools_available?
      classes.concat(MEDIA_TOOL_CLASSES) if media_tools_available?
      classes
    end

    CHAT_SCOPED_TOOL_CLASSES = [
      AnalyzeImage,
      CreateMemo,
      UpdateMemo
    ].freeze

    def tool_instances(chat)
      tool_classes.map do |tool_class|
        CHAT_SCOPED_TOOL_CLASSES.include?(tool_class) ? tool_class.new(chat: chat) : tool_class.new
      end
    end

    def apply!(llm_chat, chat:)
      tools = tool_instances(chat)
      return llm_chat if tools.empty?

      instructions = [TOOL_ORCHESTRATION_INSTRUCTIONS]
      instructions << MEMO_TOOLS_INSTRUCTIONS if memo_tools_available?
      if web_tools_available?
        instructions << WEB_TOOLS_INSTRUCTIONS
      elsif tools.any? { |tool| tool.is_a?(FetchUrl) }
        instructions << FETCH_URL_INSTRUCTIONS
      end
      instructions << VISION_TOOLS_INSTRUCTIONS if vision_tools_available?
      instructions << MEDIA_TOOLS_INSTRUCTIONS if media_tools_available?

      llm_chat.with_tools(*tools)
              .with_instructions(instructions.compact.join(" "), append: true)
    end

    def vision_service
      @vision_service ||= VisionChatService.new
    end

    def client
      TsurezureClient.new
    end

    def tsuzura_client
      TsuzuraClient.new
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
      @vision_service = nil if instance_variable_defined?(:@vision_service)
    end
  end
end
