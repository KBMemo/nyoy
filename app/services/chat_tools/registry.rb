# frozen_string_literal: true

module ChatTools
  module Registry
    MEMO_TOOLS_INSTRUCTIONS_INJECT = <<~TEXT.squish
      徒然（tsuredure）メモツールが利用可能です。
      関連メモの抜粋は自動で参照コンテキストに含まれます。
      さらに探すときは search_memos、本文が必要なときは get_memo を使ってください。
      get_memo で読む本文は AsciiDoc ですが、そのまま理解して Markdown で回答してください。
    TEXT

    MEMO_WRITE_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      create_memo はユーザーが明示的に保存を求めたときだけ使ってください。
      update_memo では必ず get_memo で取得した updated_at を渡してください。
      create_memo / update_memo の body は Markdown で書いてください（徒然側で AsciiDoc に変換）。
      Chat に葛籠へアーカイブ済みの添付画像がある場合、image::media: マクロは自動で本文末尾に挿入されます（手書き不要）。
    TEXT

    MEMO_TOOLS_INSTRUCTIONS_TOOL = <<~TEXT.squish
      徒然（tsuredure）メモツールが利用可能です。
      過去の自分のメモの内容が回答に必要なときは recall_memos（意味検索で関連抜粋を取得）を呼んでください。
      タイトル一覧をキーワードで探すだけなら search_memos、本文全体が必要なら get_memo を使ってください。
      get_memo で読む本文は AsciiDoc ですが、そのまま理解して Markdown で回答してください。
    TEXT

    TOOL_ORCHESTRATION_INSTRUCTIONS = <<~TEXT.squish
      ツールは必要なときだけ使う。ユーザーの質問を読んでから選ぶ。
      回答に必要な情報が会話履歴や参照コンテキストだけでは不足している場合は、利用可能な検索・取得ツールで確認してから回答してよい。
      最新の事実・ニュース・Web 上の情報 → web_search（詳細は fetch_url）。
      過去の自分のメモ → recall_memos（関連知識を意味検索）。一覧探索は search_memos、本文は get_memo。
      添付画像の視覚的内容（写っているもの・文字・見た目）→ analyze_image。
      画像が添付されていても、質問がテキストだけで答えられるなら analyze_image は使わない。
      複数のツールが必要なら順序よく組み合わせてよい。同じ URL や同じクエリを無駄に繰り返さない。
      ユーザーが URL を明示した場合は web_search を挟まず fetch_url で直接取得する。
      ツールは一度に1つずつ呼び、結果を受け取ってから次を判断する（同時に複数の呼び出しを並べない）。
    TEXT

    WEB_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      web_search（searfront）で Web 検索、fetch_url で HTML/テキスト本文の短いプレビューを取得できます。
      web_search の content は URL 選定用の短いスニペットです。content_truncated: true の結果で詳細が必要な場合だけ fetch_url を使ってください。
      fetch_url は content_preview のみ返し、truncated: true のときは search_fetched_page(page_id, query) で続きを探します。
      fetch_url は一度に1件の URL だけ指定します（複数 URL を同時に並べない）。結果を受け取ってから、必要なら次の URL を fetch_url で取得できます。
      ツール結果に [TOOL_LIMIT_REACHED] または [TOOL_ERROR] が含まれる場合は失敗として扱い、RETRYABLE: false のときは同じツールを繰り返し呼び出さないでください。
      CODE: URL_ALREADY_FETCHED / FETCH_LIMIT_EXCEEDED / SEARCH_LIMIT_EXCEEDED は再試行禁止です。
      CODE: QUERY_ALREADY_SEARCHED も再試行禁止です。同じ検索結果を使って回答してください。
      検索はクエリを絞って少ない回数で済ませ、本文取得は必要な HTML ページだけに限定してください。
      PDF は取得対象外です（検索結果の PDF はスキップされます）。PDF 以外の HTML を選んでください。
      fetch_url は公開 Web の http/https URL のみ取得できます。
    TEXT

    FETCH_URL_INSTRUCTIONS = <<~TEXT.squish
      fetch_url で公開 Web ページの短いプレビューを取得できます。http/https の HTML/テキストのみ。PDF は不可。
      truncated: true のときは fetch_url を再実行せず search_fetched_page を使ってください。
      fetch_url は一度に1件の URL だけ指定します。結果を受け取ってから、必要なら次の URL を取得できます（同時に複数を並べない）。HTML ページは readability-js-server で本文抽出します。
      [TOOL_LIMIT_REACHED] / [TOOL_ERROR] が返り CODE に URL_ALREADY_FETCHED や FETCH_LIMIT_EXCEEDED がある場合は fetch_url を再試行せず、既得の情報で回答してください。
    TEXT

    VISION_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      analyze_image は vision LLM で画像を解析する。添付画像または tsuzura_media_id を指定できる。
      画像の説明・OCR・「何が写っているか」など視覚情報が回答に不可欠なときだけ使う。
      メッセージ本文だけで足りる場合、Web 検索で足りる場合、添付が無関係な場合は使わない。
      使うときは prompt に具体的な質問を渡す。
    TEXT

    MEDIA_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      list_albums / get_media で葛籠（tsuzura）に保存されたメディアを参照できます。
      Bearer 認証で GET /v1/media/:id/file からバイナリ取得可能です（如意は TsuzuraClient#download_media）。
      Chat に添付した画像は「Nyoy Chat」アルバムへ自動アーカイブされ、メタデータに tsuzura_media_id が付きます。
      create_memo / update_memo 実行時に image::media: マクロが自動挿入されます。
    TEXT

    SAMPLING_TOOLS_INSTRUCTIONS = <<~TEXT.squish
      list_sampling_presets で推奨サンプリング一覧を取得できる。
      apply_sampling_preset はユーザーが明示的にサンプリングや温度などの変更を求めたときだけ使い、
      会話の llm_params をプリセットで上書きする。勝手に変更しない。
    TEXT

    SAMPLING_READ_ONLY_INSTRUCTIONS = <<~TEXT.squish
      list_sampling_presets で推奨サンプリング一覧を取得できる。
      会話設定の変更はメインLLMのツールでは行わない。
    TEXT

    MEMO_TOOL_CLASSES = [
      SearchMemos,
      GetMemo,
      CreateMemo,
      UpdateMemo
    ].freeze

    WEB_TOOL_CLASSES = [
      WebSearch,
      FetchUrl,
      SearchFetchedPage
    ].freeze

    VISION_TOOL_CLASSES = [
      AnalyzeImage
    ].freeze

    MEDIA_TOOL_CLASSES = [
      ListAlbums,
      GetMedia
    ].freeze

    SAMPLING_TOOL_CLASSES = [
      ListSamplingPresets,
      ApplySamplingPreset
    ].freeze

    module_function

    def available?
      tool_classes.any?
    end

    def memo_tools_available?
      NyoyConnectionStore.enabled?(:kbmemo) && NyoyConnectionStore.api_token(:kbmemo).present?
    end

    def web_tools_available?
      NyoyConnectionStore.enabled?(:searfront) &&
        NyoyConnectionStore.url(:searfront).present? &&
        NyoyConnectionStore.api_token(:searfront).present?
    end

    def vision_tools_available?
      LlmUsageResolver.resolve("vision.image_understanding").present?
    end

    def media_tools_available?
      NyoyConnectionStore.enabled?(:tsuzura) && NyoyConnectionStore.api_token(:tsuzura).present?
    end

    def rag_tool_available?
      ChatMemoRagInjector.tool_mode?
    end

    def tool_classes(scope: :main_llm)
      classes = all_tool_classes
      return classes if scope == :mcp || scope == :all

      MainLlmToolPolicy.filter(classes)
    end

    def all_tool_classes
      classes = []
      classes.concat(MEMO_TOOL_CLASSES) if memo_tools_available?
      classes << RecallMemos if rag_tool_available?
      classes << WebSearch if web_tools_available?
      classes << FetchUrl
      classes << SearchFetchedPage
      classes.concat(VISION_TOOL_CLASSES) if vision_tools_available?
      classes.concat(MEDIA_TOOL_CLASSES) if media_tools_available?
      classes.concat(SAMPLING_TOOL_CLASSES)
      classes
    end

    CHAT_SCOPED_TOOL_CLASSES = [
      AnalyzeImage,
      CreateMemo,
      UpdateMemo,
      RecallMemos,
      ApplySamplingPreset
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

      instructions = [ TOOL_ORCHESTRATION_INSTRUCTIONS ]
      instructions << memo_tools_instructions(tools) if memo_tools_available?
      if web_tools_available?
        instructions << WEB_TOOLS_INSTRUCTIONS
      elsif tools.any? { |tool| tool.is_a?(FetchUrl) }
        instructions << FETCH_URL_INSTRUCTIONS
      end
      instructions << VISION_TOOLS_INSTRUCTIONS if vision_tools_available?
      instructions << MEDIA_TOOLS_INSTRUCTIONS if media_tools_available?
      instructions << sampling_tools_instructions(tools)

      llm_chat.with_tools(*tools, calls: :one, concurrency: false)
              .with_instructions(instructions.compact.join(" "), append: true)
    end

    def memo_tools_instructions(tools)
      text = rag_tool_available? ? MEMO_TOOLS_INSTRUCTIONS_TOOL : MEMO_TOOLS_INSTRUCTIONS_INJECT
      return text unless write_tools_present?(tools)

      [ text, MEMO_WRITE_TOOLS_INSTRUCTIONS ].join(" ")
    end

    def sampling_tools_instructions(tools)
      return SAMPLING_TOOLS_INSTRUCTIONS if tool_present?(tools, "apply_sampling_preset")
      return SAMPLING_READ_ONLY_INSTRUCTIONS if tool_present?(tools, "list_sampling_presets")

      nil
    end

    def write_tools_present?(tools)
      tools.any? { |tool| MainLlmToolPolicy.write_tool?(tool.name) }
    end

    def tool_present?(tools, name)
      tools.any? { |tool| tool.name == name }
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

    def web_search_client
      SearfrontClient.new
    end

    def searxng_client
      web_search_client
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
