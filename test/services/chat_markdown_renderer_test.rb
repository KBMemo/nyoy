# frozen_string_literal: true

require "test_helper"

class ChatMarkdownRendererTest < ActiveSupport::TestCase
  test "renders gfm headings lists and code blocks" do
    markdown = <<~MD.strip
      ### 手順

      **太字** と `inline`

      - item 1
      - item 2

      ```bash
      cmake ..
      ```
    MD

    html = ChatMarkdownRenderer.render(markdown)

    assert_includes html, "<h3"
    assert_includes html, "<strong>太字</strong>"
    assert_includes html, "<code>inline</code>"
    assert_includes html, "<ul>"
    assert_includes html, "<pre>"
    assert_includes html, "cmake .."
  end

  test "sanitizes unsafe html" do
    html = ChatMarkdownRenderer.render('<script>alert(1)</script>**safe**')

    assert_not_includes html, "<script>"
    assert_includes html, "<strong>safe</strong>"
  end

  test "returns empty safe string for blank input" do
    assert_equal "", ChatMarkdownRenderer.render("")
    assert_equal "", ChatMarkdownRenderer.render(nil)
  end

  test "preserves single newlines as line breaks" do
    html = ChatMarkdownRenderer.render("1行目\n2行目")

    assert_includes html, "<br>"
    assert_includes html, "1行目"
    assert_includes html, "2行目"
  end

  test "renders gfm tables after headings without a blank line" do
    markdown = <<~MD.strip
      ### 品種の特徴
      | 項目 | 内容 |
      |——|——|
      | 学名 | Hydrangea macrophylla |
      続きの説明
    MD

    html = ChatMarkdownRenderer.render(markdown)

    assert_includes html, "<table>"
    assert_includes html, "<thead>"
    assert_includes html, "<th>項目</th>"
    assert_includes html, "<th>内容</th>"
    assert_includes html, "<td>学名</td>"
    assert_includes html, "Hydrangea macrophylla"
    assert_includes html, "<p>続きの説明</p>"
    refute_includes html, "| 項目 |"
  end

  test "normalizes fullwidth pipes in tables" do
    markdown = "｜A｜B｜\n｜---｜---｜\n｜1｜2｜"
    html = ChatMarkdownRenderer.render(markdown)

    assert_includes html, "<table>"
    assert_includes html, "<th>A</th>"
    assert_includes html, "<td>1</td>"
  end
end
