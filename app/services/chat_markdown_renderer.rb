# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

class ChatMarkdownRenderer
  ALLOWED_TAGS = %w[
    p br hr h1 h2 h3 h4 h5 h6 ul ol li strong em b i del
    code pre blockquote a table thead tbody tr th td
  ].freeze

  ALLOWED_ATTRIBUTES = %w[href title].freeze

  def self.render(text)
    new.render(text)
  end

  def render(text)
    return "".html_safe if text.blank?

    html = Kramdown::Document.new(
      text.to_s,
      input: "GFM",
      hard_wrap: true,
      syntax_highlighter: nil
    ).to_html

    ActionController::Base.helpers.sanitize(
      html,
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTRIBUTES
    )
  end
end
