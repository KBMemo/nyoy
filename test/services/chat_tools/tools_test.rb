# frozen_string_literal: true

require "test_helper"

class ChatToolsTest < ActiveSupport::TestCase
  setup do
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
  end

  test "web_search returns results from client" do
    calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:search) do |**kwargs|
      calls << kwargs
      { "results" => [{ "title" => "Ruby", "url" => "https://ruby-lang.org" }] }
    end
    ChatTools::Registry.define_singleton_method(:searxng_client) { fake_client }

    result = ChatTools::WebSearch.new.execute(q: "ruby")

    assert_equal "ruby", calls.first[:q]
    assert_equal 1, result["results"].size
  ensure
    ChatTools::Registry.singleton_class.remove_method(:searxng_client)
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
    ChatTools::Registry.singleton_class.remove_method(:url_fetcher)
  end
end
