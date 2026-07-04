# frozen_string_literal: true

module ChatTools
  module Registry
    MEMO_TOOLS_INSTRUCTIONS_INJECT = <<~TEXT.squish
      徒然（tsuredure）メモツールが利用可能です。
      関連メモの抜粋は自動で参照コンテキストに含まれます。
      さらに探すときは search_memos、本文が必要なときは get_memo を使ってください。
      create_memo はユーザーが明示的に保存を求めたときだけ使ってください。
      update_memo では必ず get_memo で取得した updated_at を渡してください。
      create_memo / update_memo の body は Markdown で書いてください（徒然側で AsciiDoc に変換）。
      Chat に葛籠へアーカイブ済みの添付画像がある場合、image::media: マクロは自動で本文末尾に挿入されます（手書き不要）。
      get_memo で読む本文は AsciiDoc ですが、そのまま理解して Markdown で更新してください。
    TEXT

    MEMO_TOOLS_INSTRUCTIONS_TOOL = <<~TEXT.squish
      徒然（tsuredure）メモツールが利用可能です。
      過去の自分のメモの内容が回答に必要なときは recall_memos（意味検索で関連抜粋を取得）を呼んでください。
      タイトル一覧をキーワードで探すだけなら search_memos、本文全体が必要なら get_memo を使ってください。
      create_memo はユーザーが明示的に保存を求めたときだけ使ってください。
      update_memo では必ず get_memo で取得した updated_at を渡してください。
      create_memo / update_memo の body は Markdown で書いてください（徒然側で AsciiDoc に変換）。
      Chat に葛籠へアーカイブ済みの添付画像がある場合、image::media: マクロは自動で本文末尾に挿入されます（手書き不要）。
      get_memo で読む本文は AsciiDoc ですが、そのまま理解して Markdown で更新してください。
    TEXT

    TOOL_ORCHESTRATION_INSTRUCTIONS = <<~TEXT.squish
      ツールは必要なときだけ使う。ユーザーの質問を読んでから選ぶ。
      最新の事実・ニュース・Web 上の情報 → web_search（詳細は fetch_url）。
      過去の自分のメモ → recall_memos（関連知識を意味検索）。一覧探索は search_memos、本文は get_memo。
      添付画像の視覚的内容（写っているもの・文字・見た目）→ analyze_image。
      画像が添付されていても、質問がテキストだけで答えられるなら analyze_image は使わない。
      複数のツールが必要なら順序よく組み合わせてよいが、同じ種類のツールを何度も繰り返さない。
    TEXT

    WEB_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      web_search（SearXNG）で Web 検索、fetch_url で HTML/テキスト本文を取得できます。
      web_search / fetch_url の1回の応答あたりの上限は接続設定（SearXNG）に従います。
      検索はクエリを絞って少ない回数で済ませ、本文取得は必要な HTML ページだけに限定してください。
      PDF は取得対象外です（検索結果の PDF はスキップされます）。PDF 以外の HTML を選んでください。
      fetch_url は公開 Web の http/https URL のみ取得できます。
    TEXT

    FETCH_URL_INSTRUCTIONS = <<~TEXT.squish
      fetch_url で公開 Web ページの本文を取得できます。http/https の HTML/テキストのみ。PDF は不可。
      1回の応答あたりの上限は接続設定に従います。HTML ページは readability-js-server で本文抽出します。
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

    def rag_tool_available?
      ChatMemoRagInjector.tool_mode?
    end

    def tool_classes
      classes = []
      classes.concat(MEMO_TOOL_CLASSES) if memo_tools_available?
      classes << RecallMemos if rag_tool_available?
      classes << WebSearch if web_tools_available?
      classes << FetchUrl
      classes.concat(VISION_TOOL_CLASSES) if vision_tools_available?
      classes.concat(MEDIA_TOOL_CLASSES) if media_tools_available?
      classes
    end

    CHAT_SCOPED_TOOL_CLASSES = [
      AnalyzeImage,
      CreateMemo,
      UpdateMemo,
      RecallMemos
    ].freeze

    WEB_BUDGET_TOOL_CLASSES = [
      WebSearch,
      FetchUrl
    ].freeze

    def tool_instances(chat)
      web_budget = WebToolBudget.from_settings

      tool_classes.map do |tool_class|
        if CHAT_SCOPED_TOOL_CLASSES.include?(tool_class)
          tool_class.new(chat: chat)
        elsif WEB_BUDGET_TOOL_CLASSES.include?(tool_class)
          tool_class.new(budget: web_budget)
        else
          tool_class.new
        end
      end
    end

    def apply!(llm_chat, chat:)
      tools = tool_instances(chat)
      return llm_chat if tools.empty?

      instructions = [TOOL_ORCHESTRATION_INSTRUCTIONS]
      instructions << memo_tools_instructions if memo_tools_available?
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

    def memo_tools_instructions
      rag_tool_available? ? MEMO_TOOLS_INSTRUCTIONS_TOOL : MEMO_TOOLS_INSTRUCTIONS_INJECT
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
