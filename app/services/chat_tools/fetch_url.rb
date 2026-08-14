# frozen_string_literal: true

module ChatTools
  class FetchUrl < RubyLLM::Tool
    MAX_RETURN_BYTES = 6_000

    description <<~DESC.squish
      指定 URL の HTML/テキスト本文を取得する。
      readability-js-server で本文抽出し、長いページは短い content_preview だけ返す。
      truncated: true の場合、同じ URL を fetch_url で再取得してはいけない。
      長いページの続きは search_fetched_page(page_id, query) を使う。
    DESC

    def initialize(budget: nil, chat: nil)
      @budget = budget || WebToolBudget.from_settings
      @chat = chat
    end

    def name
      "fetch_url"
    end

    param :url, desc: "取得する http/https URL（PDF 不可。空白を入れず、ユーザーが書いた文字列をそのまま渡す）", required: true

    def execute(url:)
      url = resolve_url(url)

      if PdfUrl.blocked?(url)
        return ToolResponse.error(
          tool: "fetch_url",
          code: "PDF_BLOCKED",
          retryable: false,
          url: url,
          message: "PDF は現在取得対象外です。",
          next_action: "PDF ではなく HTML ページを使うか、既存情報だけで回答してください。"
        )
      end

      if (error = @budget.consume_fetch!(url: url))
        return error
      end

      result = Registry.url_fetcher.fetch(
        url,
        max_bytes: MAX_RETURN_BYTES,
        include_full_text: true
      )

      page_id = FetchedPageCache.store(
        url: result[:url],
        title: result[:title],
        text: result.delete(:full_text).to_s.presence || result[:text].to_s
      )

      truncated = result[:truncated] == true

      ToolResponse.preview(
        ok: true,
        tool: "fetch_url",
        page_id: page_id,
        url: result[:url],
        status: result[:status],
        title: result[:title],
        site_name: result[:site_name],
        excerpt: result[:excerpt],
        extractor: result[:extractor],
        content_preview: result[:text],
        returned_bytes_limit: MAX_RETURN_BYTES,
        truncated: truncated,
        available_tools: truncated ? ["search_fetched_page"] : nil,
        next_action: truncated_next_action(truncated)
      )
    rescue SafeUrlFetcher::Error => e
      ToolResponse.error(
        tool: "fetch_url",
        code: "FETCH_FAILED",
        retryable: false,
        url: url,
        message: e.message,
        next_action: "同じ URL を再取得せず、別の情報源または既存情報で回答してください。"
      )
    end

    private

    def resolve_url(raw)
      recovered = HttpUrl.recover_from_explicit(raw, explicit_urls_from_chat)
      HttpUrl.normalize(recovered || raw)
    end

    def explicit_urls_from_chat
      return [] unless @chat.respond_to?(:messages)

      HttpUrl.extract_all(@chat.messages.where(role: "user").order(:created_at).last&.content)
    end

    def truncated_next_action(truncated)
      if truncated
        "本文は長いため一部のみです。同じ URL を fetch_url で再取得せず、必要な箇所は search_fetched_page(page_id, query) を使ってください。"
      else
        "この content_preview を使って回答してください。"
      end
    end
  end
end
