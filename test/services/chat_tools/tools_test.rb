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
end
