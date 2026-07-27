# frozen_string_literal: true

require "test_helper"

class TsurezureMemoUrlTest < ActiveSupport::TestCase
  test "returns absolute url unchanged" do
    memo = { "url" => "https://kbmemo.example.com/memos/01JMEMO", "uid" => "01JMEMO" }
    assert_equal "https://kbmemo.example.com/memos/01JMEMO", TsurezureMemoUrl.absolute(memo)
  end

  test "builds absolute url from relative path" do
    memo = { "url" => "/memos/1047", "id" => 1047 }
    assert_equal "https://kbmemo.example.com/memos/1047", TsurezureMemoUrl.absolute(memo, base_url: "https://kbmemo.example.com/api/v1")
  end

  test "builds absolute url from uid when url missing" do
    memo = { "uid" => "01JMEMO", "id" => 42 }
    assert_equal "http://localhost:3000/memos/01JMEMO", TsurezureMemoUrl.absolute(memo, base_url: "http://localhost:3000/api/v1")
  end
end
