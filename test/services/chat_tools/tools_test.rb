# frozen_string_literal: true

require "base64"
require "test_helper"

class ChatToolsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    ChatTools::Registry.reset_client!
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    ChatTools::Registry.reset_client!
    Rails.cache = @original_cache if defined?(@original_cache)
  end

  test "tool names match openapi mapping" do
    assert_equal "search_memos", ChatTools::SearchMemos.new.name
    assert_equal "get_memo", ChatTools::GetMemo.new.name
    assert_equal "create_memo", ChatTools::CreateMemo.new.name
    assert_equal "update_memo", ChatTools::UpdateMemo.new.name
    assert_equal "web_search", ChatTools::WebSearch.new.name
    assert_equal "fetch_url", ChatTools::FetchUrl.new.name
    assert_equal "search_fetched_page", ChatTools::SearchFetchedPage.new.name
    assert_equal "analyze_image", ChatTools::AnalyzeImage.new(chat: Chat.new).name
    assert_equal "list_albums", ChatTools::ListAlbums.new.name
    assert_equal "get_media", ChatTools::GetMedia.new.name
    assert_equal "list_sampling_presets", ChatTools::ListSamplingPresets.new.name
    assert_equal "apply_sampling_preset", ChatTools::ApplySamplingPreset.new.name
  end

  test "web_search returns results from client" do
    calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:search) do |**kwargs|
      calls << kwargs
      { "results" => [{ "title" => "Ruby", "url" => "https://ruby-lang.org" }] }
    end
    original_web_search_client = ChatTools::Registry.method(:web_search_client)
    ChatTools::Registry.define_singleton_method(:web_search_client) { fake_client }

    result = ChatTools::WebSearch.new.execute(q: "ruby")

    assert_equal "ruby", calls.first[:q]
    assert_equal 1, result["results"].size
  ensure
    ChatTools::Registry.define_singleton_method(:web_search_client, original_web_search_client) if defined?(original_web_search_client)
  end

  test "web_search filters pdf results and limits calls per turn" do
    calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:search) do |**kwargs|
      calls << kwargs
      {
        "results" => [
          { "title" => "HTML", "url" => "https://example.com/page" },
          { "title" => "PDF", "url" => "https://example.com/doc.pdf" }
        ]
      }
    end
    original_web_search_client = ChatTools::Registry.method(:web_search_client)
    ChatTools::Registry.define_singleton_method(:web_search_client) { fake_client }

    budget = ChatTools::WebToolBudget.new(max_searches: 2, max_fetches: 3)
    tool = ChatTools::WebSearch.new(budget: budget)

    first = tool.execute(q: "ruby")
    second = tool.execute(q: "rails")
    third = tool.execute(q: "again")

    assert_equal 1, first["results"].size
    assert_equal ["https://example.com/doc.pdf"], first["skipped_pdf_urls"]
    assert_equal 2, calls.size
    assert_match(/TOOL_LIMIT_REACHED/, third)
    assert_match(/SEARCH_LIMIT_EXCEEDED/, third)
    assert_match(/最大 2 回/, third)
  ensure
    ChatTools::Registry.define_singleton_method(:web_search_client, original_web_search_client) if defined?(original_web_search_client)
  end

  test "web_search rejects an equivalent query repeated in one turn" do
    calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:search) do |**kwargs|
      calls << kwargs
      { "results" => [ { "title" => "Ruby", "url" => "https://ruby-lang.org" } ] }
    end
    original_web_search_client = ChatTools::Registry.method(:web_search_client)
    ChatTools::Registry.define_singleton_method(:web_search_client) { fake_client }

    budget = ChatTools::WebToolBudget.new(max_searches: 2, max_fetches: 3)
    tool = ChatTools::WebSearch.new(budget: budget)

    tool.execute(q: "Ruby  Rails")
    duplicate = tool.execute(q: "ruby rails")

    assert_match(/TOOL_ERROR/, duplicate)
    assert_match(/QUERY_ALREADY_SEARCHED/, duplicate)
    assert_equal 1, calls.size
    assert_equal 1, budget.searches
  ensure
    ChatTools::Registry.define_singleton_method(:web_search_client, original_web_search_client) if defined?(original_web_search_client)
  end

  test "web_search limits long result snippets" do
    fake_client = Object.new
    fake_client.define_singleton_method(:search) do |**|
      {
        "results" => [
          { "title" => "Long", "url" => "https://example.com/long", "content" => "あ" * 2_000 },
          { "title" => "Short", "url" => "https://example.com/short", "content" => "短い" }
        ]
      }
    end
    original_web_search_client = ChatTools::Registry.method(:web_search_client)
    ChatTools::Registry.define_singleton_method(:web_search_client) { fake_client }

    result = ChatTools::WebSearch.new.execute(q: "ruby")

    assert_operator result.dig("results", 0, "content").length, :<=, ChatTools::WebSearch::MAX_SNIPPET_CHARS
    assert_equal true, result.dig("results", 0, "content_truncated")
    assert_nil result.dig("results", 1, "content_truncated")
    assert_equal 1, result["truncated_result_count"]
    assert_equal ChatTools::WebSearch::MAX_SNIPPET_CHARS, result["result_content_limit"]
  ensure
    ChatTools::Registry.define_singleton_method(:web_search_client, original_web_search_client) if defined?(original_web_search_client)
  end

  test "web search query history survives graph budget restoration" do
    budget = ChatTools::WebToolBudget.new(max_searches: 2, max_fetches: 3)
    assert_nil budget.consume_search!(query: "Ruby Rails")

    restored = ChatTools::WebToolBudget.from_graph_budget(budget.to_graph_budget)
    duplicate = restored.consume_search!(query: "ruby  rails")

    assert_match(/QUERY_ALREADY_SEARCHED/, duplicate)
    assert_equal [ "ruby rails" ], restored.to_graph_budget["searched_queries"]
  end

  test "fetch_url returns page preview json" do
    calls = []
    fake_fetcher = Object.new
    fake_fetcher.define_singleton_method(:fetch) do |url, **kwargs|
      calls << { url: url, kwargs: kwargs }
      { url: url, status: 200, title: "Example", text: "Hello", full_text: "Hello world" }
    end
    original_url_fetcher = ChatTools::Registry.method(:url_fetcher)
    ChatTools::Registry.define_singleton_method(:url_fetcher) { fake_fetcher }

    result = JSON.parse(ChatTools::FetchUrl.new.execute(url: "https://example.com"))

    assert_equal "https://example.com", calls.first[:url]
    assert_equal 6_000, calls.first[:kwargs][:max_bytes]
    assert_equal true, calls.first[:kwargs][:include_full_text]
    assert_equal "Hello", result["content_preview"]
    assert result["page_id"].present?
    assert_equal true, result["ok"]
  ensure
    ChatTools::Registry.define_singleton_method(:url_fetcher, original_url_fetcher) if defined?(original_url_fetcher)
  end

  test "fetch_url repairs llm-inserted spaces before fetching" do
    calls = []
    fake_fetcher = Object.new
    fake_fetcher.define_singleton_method(:fetch) do |url, **|
      calls << url
      { url: url, status: 200, text: "ok", full_text: "ok" }
    end
    original_url_fetcher = ChatTools::Registry.method(:url_fetcher)
    ChatTools::Registry.define_singleton_method(:url_fetcher) { fake_fetcher }

    original = "https://store.toto-dream.com/dcs/subos/screen/pi01/spin000/PGSPIN00001DisptotoLotInfo.form?holdCntId=1645"
    spaced = "https://store.toto-dream.com/dcs subos/screen/pi01/spin 000/PG SPIN00001 Disptoto LotInfo.form? holdCntId=1645"
    result = JSON.parse(ChatTools::FetchUrl.new.execute(url: spaced))

    assert_equal [ original ], calls
    assert_equal original, result["url"]
  ensure
    ChatTools::Registry.define_singleton_method(:url_fetcher, original_url_fetcher) if defined?(original_url_fetcher)
  end

  test "fetch_url prefers the explicit user url when the tool argument is corrupted" do
    calls = []
    fake_fetcher = Object.new
    fake_fetcher.define_singleton_method(:fetch) do |url, **|
      calls << url
      { url: url, status: 200, text: "ok", full_text: "ok" }
    end
    original_url_fetcher = ChatTools::Registry.method(:url_fetcher)
    ChatTools::Registry.define_singleton_method(:url_fetcher) { fake_fetcher }

    original = "https://store.toto-dream.com/dcs/subos/screen/pi01/spin000/PGSPIN00001DisptotoLotInfo.form?holdCntId=1645"
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    chat.messages.create!(role: :user, content: original)
    spaced = "https://store.toto-dream.com/dcs subos/screen/pi01/spin 000/PG SPIN00001 Disptoto LotInfo.form? holdCntId=1645"

    ChatTools::FetchUrl.new(chat: chat).execute(url: spaced)

    assert_equal [ original ], calls
  ensure
    ChatTools::Registry.define_singleton_method(:url_fetcher, original_url_fetcher) if defined?(original_url_fetcher)
  end

  test "fetch_url rejects pdf and limits calls per turn" do
    calls = []
    fake_fetcher = Object.new
    fake_fetcher.define_singleton_method(:fetch) do |url, **|
      calls << url
      { url: url, status: 200, text: "ok", full_text: "ok" }
    end
    original_url_fetcher = ChatTools::Registry.method(:url_fetcher)
    ChatTools::Registry.define_singleton_method(:url_fetcher) { fake_fetcher }

    budget = ChatTools::WebToolBudget.new(max_searches: 2, max_fetches: 2)
    tool = ChatTools::FetchUrl.new(budget: budget)

    pdf = tool.execute(url: "https://example.com/a.pdf")
    first = JSON.parse(tool.execute(url: "https://example.com/1"))
    second = JSON.parse(tool.execute(url: "https://example.com/2"))
    third = tool.execute(url: "https://example.com/3")

    assert_match(/TOOL_ERROR/, pdf)
    assert_match(/PDF_BLOCKED/, pdf)
    assert_match(/PDF/, pdf)
    assert_equal "ok", first["content_preview"]
    assert_equal "ok", second["content_preview"]
    assert_match(/TOOL_LIMIT_REACHED/, third)
    assert_match(/FETCH_LIMIT_EXCEEDED/, third)
    assert_match(/最大 2 回/, third)
    assert_equal 2, calls.size
  ensure
    ChatTools::Registry.define_singleton_method(:url_fetcher, original_url_fetcher) if defined?(original_url_fetcher)
  end

  test "fetch_url rejects duplicate url without calling fetcher again" do
    calls = []
    fake_fetcher = Object.new
    fake_fetcher.define_singleton_method(:fetch) do |url, **|
      calls << url
      { url: url, status: 200, text: "ok", full_text: "ok" }
    end
    original_url_fetcher = ChatTools::Registry.method(:url_fetcher)
    ChatTools::Registry.define_singleton_method(:url_fetcher) { fake_fetcher }

    budget = ChatTools::WebToolBudget.new(max_searches: 2, max_fetches: 3)
    tool = ChatTools::FetchUrl.new(budget: budget)

    first = JSON.parse(tool.execute(url: "https://example.com/page"))
    duplicate = tool.execute(url: "https://example.com/page")

    assert_equal "ok", first["content_preview"]
    assert_match(/TOOL_ERROR/, duplicate)
    assert_match(/URL_ALREADY_FETCHED/, duplicate)
    assert_equal 1, calls.size
  ensure
    ChatTools::Registry.define_singleton_method(:url_fetcher, original_url_fetcher) if defined?(original_url_fetcher)
  end

  test "search_fetched_page returns matching excerpts from cache" do
    page_id = ChatTools::FetchedPageCache.store(
      url: "https://example.com/article",
      title: "Article",
      text: "前半の本文です。試合開始時間は19時00分です。後半の本文です。"
    )

    result = JSON.parse(ChatTools::SearchFetchedPage.new.execute(page_id: page_id, query: "試合開始"))

    assert_equal true, result["ok"]
    assert_equal 1, result["matches"].size
    assert_includes result["matches"].first["excerpt"], "試合開始時間"
  ensure
    Rails.cache.clear
  end

  test "search_fetched_page removes overlapping excerpts" do
    gap = "x" * (ChatTools::SearchFetchedPage::WINDOW * 3)
    text = "retry_on exceptions retry_on" + gap + "exceptions in another section"
    page_id = ChatTools::FetchedPageCache.store(
      url: "https://example.com/article",
      title: "Article",
      text: text
    )

    result = JSON.parse(
      ChatTools::SearchFetchedPage.new.execute(page_id: page_id, query: "retry_on exceptions")
    )

    assert_equal 2, result["matches"].size
    offsets = result["matches"].map { |match| match["offset"] }
    assert_operator offsets.last - offsets.first, :>=, ChatTools::SearchFetchedPage::WINDOW
  ensure
    Rails.cache.clear
  end

  test "search_fetched_page reports missing cache" do
    result = ChatTools::SearchFetchedPage.new.execute(page_id: "missing", query: "query")

    assert_match(/TOOL_ERROR/, result)
    assert_match(/PAGE_NOT_FOUND/, result)
  end

  test "analyze_image returns vision analysis" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )
    message = chat.messages.create!(role: :user, content: "この画像は？")
    message.attachments.attach(
      io: StringIO.new(png),
      filename: "pixel.png",
      content_type: "image/png"
    )

    fake_service = Object.new
    fake_service.define_singleton_method(:analyze) do |**|
      "猫が写っています"
    end
    original_vision_service = ChatTools::Registry.method(:vision_service)
    ChatTools::Registry.define_singleton_method(:vision_service) { fake_service }

    result = ChatTools::AnalyzeImage.new(chat: chat).execute(prompt: "何が写っていますか？")

    assert_equal "猫が写っています", result[:analysis]
    assert_equal "pixel.png", result[:filename]
  ensure
    ChatTools::Registry.define_singleton_method(:vision_service, original_vision_service) if defined?(original_vision_service)
  end

  test "analyze_image reports missing attachment" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))

    result = ChatTools::AnalyzeImage.new(chat: chat).execute(prompt: "説明して")

    assert_match(/画像がありません/, result[:error])
  end

  test "analyze_image downloads tsuzura media when media id given" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    service_connections(:tsuzura).update!(api_token: "tsuzura_test", enabled: true)

    fake_client = Object.new
    fake_client.define_singleton_method(:download_media) do |media_id|
      TsuzuraClient::Download.new(data: "png-bytes", content_type: "image/png", filename: "archived.png")
    end
    captured = {}
    fake_service = Object.new
    fake_service.define_singleton_method(:analyze) do |**kwargs|
      captured[:image] = kwargs[:image]
      "葛籠の画像です"
    end

    original_client = ChatTools::Registry.method(:tsuzura_client)
    original_vision = ChatTools::Registry.method(:vision_service)
    ChatTools::Registry.define_singleton_method(:tsuzura_client) { fake_client }
    ChatTools::Registry.define_singleton_method(:vision_service) { fake_service }

    result = ChatTools::AnalyzeImage.new(chat: chat).execute(
      prompt: "何が写っていますか？",
      tsuzura_media_id: "01JARCHIVED"
    )

    assert_equal "葛籠の画像です", result[:analysis]
    assert_equal "01JARCHIVED", result[:tsuzura_media_id]
    assert_equal "png-bytes", captured[:image]
  ensure
    ChatTools::Registry.define_singleton_method(:tsuzura_client, original_client) if defined?(original_client)
    ChatTools::Registry.define_singleton_method(:vision_service, original_vision) if defined?(original_vision)
  end

  test "get_media returns metadata from client" do
    fake_client = Object.new
    fake_client.define_singleton_method(:get_media) do |media_id|
      { "id" => media_id, "original_filename" => "photo.png" }
    end
    original = ChatTools::Registry.method(:tsuzura_client)
    ChatTools::Registry.define_singleton_method(:tsuzura_client) { fake_client }

    result = ChatTools::GetMedia.new.execute(media_id: "01JTEST")

    assert_equal "01JTEST", result.dig(:media, "id")
  ensure
    ChatTools::Registry.define_singleton_method(:tsuzura_client, original) if defined?(original)
  end

  test "list_albums returns albums from client" do
    fake_client = Object.new
    fake_client.define_singleton_method(:list_albums) do
      { "albums" => [{ "id" => "01JALBUM", "title" => "Nyoy Chat" }] }
    end
    original = ChatTools::Registry.method(:tsuzura_client)
    ChatTools::Registry.define_singleton_method(:tsuzura_client) { fake_client }

    result = ChatTools::ListAlbums.new.execute

    assert_equal "Nyoy Chat", result[:albums].first["title"]
  ensure
    ChatTools::Registry.define_singleton_method(:tsuzura_client, original) if defined?(original)
  end

  test "create_memo appends chat image macros after create" do
    chat = Chat.create!(model: Model.find_by!(provider: "openai", model_id: "gpt-oss"))
    message = chat.messages.create!(role: :user, content: "保存")
    message.attachments.attach(
      io: StringIO.new("png"),
      filename: "pixel.png",
      content_type: "image/png",
      metadata: { tsuzura_media_id: "01JARCHIVED" }
    )

    calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:create_memo) do |**|
      calls << [:create]
      { "uid" => "01JMEMO", "updated_at" => "2026-07-03T10:00:00Z" }
    end
    fake_client.define_singleton_method(:update_memo) do |memo_ref, **kwargs|
      calls << [:update, memo_ref, kwargs]
      { "uid" => memo_ref, "updated_at" => "2026-07-03T10:00:01Z", "appended_media_ids" => ["01JARCHIVED"] }
    end
    original = ChatTools::Registry.method(:client)
    ChatTools::Registry.define_singleton_method(:client) { fake_client }

    result = ChatTools::CreateMemo.new(chat: chat).execute(body: "## メモ\n\n本文")

    assert_equal [:create], calls.first
    assert_equal "01JMEMO", calls.second[1]
    assert_equal "image::media:01JARCHIVED[]", calls.second[2][:append_body]
    assert_equal ["01JARCHIVED"], result["appended_media_ids"]
  ensure
    ChatTools::Registry.define_singleton_method(:client, original) if defined?(original)
  end
end
