# frozen_string_literal: true

require "base64"
require "test_helper"

class ChatToolsTest < ActiveSupport::TestCase
  setup do
    ChatModelCatalog.seed!
    ChatTools::Registry.reset_client!
  end

  teardown do
    ChatTools::Registry.reset_client!
  end

  test "tool names match openapi mapping" do
    assert_equal "search_memos", ChatTools::SearchMemos.new.name
    assert_equal "get_memo", ChatTools::GetMemo.new.name
    assert_equal "create_memo", ChatTools::CreateMemo.new.name
    assert_equal "update_memo", ChatTools::UpdateMemo.new.name
    assert_equal "web_search", ChatTools::WebSearch.new.name
    assert_equal "fetch_url", ChatTools::FetchUrl.new.name
    assert_equal "analyze_image", ChatTools::AnalyzeImage.new(chat: Chat.new).name
    assert_equal "list_albums", ChatTools::ListAlbums.new.name
    assert_equal "get_media", ChatTools::GetMedia.new.name
  end

  test "web_search returns results from client" do
    calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:search) do |**kwargs|
      calls << kwargs
      { "results" => [{ "title" => "Ruby", "url" => "https://ruby-lang.org" }] }
    end
    original_searxng_client = ChatTools::Registry.method(:searxng_client)
    ChatTools::Registry.define_singleton_method(:searxng_client) { fake_client }

    result = ChatTools::WebSearch.new.execute(q: "ruby")

    assert_equal "ruby", calls.first[:q]
    assert_equal 1, result["results"].size
  ensure
    ChatTools::Registry.define_singleton_method(:searxng_client, original_searxng_client) if defined?(original_searxng_client)
  end

  test "fetch_url returns page text" do
    calls = []
    fake_fetcher = Object.new
    fake_fetcher.define_singleton_method(:fetch) do |url|
      calls << url
      { url: url, status: 200, title: "Example", text: "Hello" }
    end
    ChatTools::Registry.define_singleton_method(:url_fetcher) { fake_fetcher }

    result = ChatTools::FetchUrl.new.execute(url: "https://example.com")

    assert_equal "https://example.com", calls.first
    assert_equal "Hello", result[:text]
  ensure
    ChatTools::Registry.reset_client!
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
