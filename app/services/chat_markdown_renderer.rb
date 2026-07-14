# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

class ChatMarkdownRenderer
  ALLOWED_TAGS = %w[
    p br hr h1 h2 h3 h4 h5 h6 ul ol li strong em b i del
    code pre blockquote a table thead tbody tr th td
  ].freeze

  ALLOWED_ATTRIBUTES = %w[href title].freeze

  # ASCII hyphen plus common unicode dashes LLMs emit in table separators.
  DASH_CHARS = "-–—─−－﹣".freeze
  TABLE_ROW = /\A\s*[|｜].+[|｜]\s*\z/
  SEPARATOR_CELL = /:?[#{Regexp.escape(DASH_CHARS)}]{2,}:?/
  SEPARATOR_ROW = /\A\s*[|｜]?\s*#{SEPARATOR_CELL}(?:\s*[|｜]\s*#{SEPARATOR_CELL})+\s*[|｜]?\s*\z/

  def self.render(text)
    new.render(text)
  end

  def render(text)
    return "".html_safe if text.blank?

    html = Kramdown::Document.new(
      normalize_markdown(text.to_s),
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

  private

  def normalize_markdown(text)
    isolate_gfm_tables(text.gsub("\r\n", "\n").gsub("\r", "\n"))
  end

  # GFM tables need blank lines around the block when hard_wrap is on, and
  # LLM output often uses fullwidth pipes / unicode dashes without those blanks.
  def isolate_gfm_tables(text)
    lines = text.split("\n", -1)
    out = []
    i = 0

    while i < lines.length
      if table_block_at?(lines, i)
        out << "" unless out.empty? || out.last.to_s.strip.empty?

        while i < lines.length && table_line?(lines[i])
          out << normalize_table_line(lines[i])
          i += 1
        end

        out << "" unless i >= lines.length || lines[i].to_s.strip.empty? || out.last.to_s.empty?
        next
      end

      out << lines[i]
      i += 1
    end

    out.join("\n")
  end

  def table_block_at?(lines, index)
    return false unless table_line?(lines[index])
    return false if index.positive? && table_line?(lines[index - 1])

    nxt = lines[index + 1]
    return false if nxt.nil?

    separator_row?(nxt) || table_row?(nxt)
  end

  def table_line?(line)
    table_row?(line) || separator_row?(line)
  end

  def table_row?(line)
    line.to_s.match?(TABLE_ROW)
  end

  def separator_row?(line)
    line.to_s.match?(SEPARATOR_ROW)
  end

  def normalize_table_line(line)
    normalized = line.to_s.tr("｜", "|")
    return normalized unless separator_row?(normalized)

    normalized.gsub(/[#{Regexp.escape(DASH_CHARS)}]{2,}/, "---")
  end
end
