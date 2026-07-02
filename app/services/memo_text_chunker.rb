# frozen_string_literal: true

class MemoTextChunker
  def initialize(max_chars: Rails.application.config.x.nyoy.memo_chunk_max_chars)
    @max_chars = max_chars.to_i.positive? ? max_chars.to_i : 1500
  end

  def chunk(body)
    text = body.to_s.strip
    return [] if text.blank?

    sections = split_sections(text)
    sections.flat_map { |section| split_oversized(section) }.reject(&:blank?)
  end

  private

  def split_sections(text)
    parts = text.split(/\n(?==+ )/)
    parts.flat_map { |part| part.split(/\n{2,}/) }.map(&:strip).reject(&:blank?)
  end

  def split_oversized(section)
    return [section] if section.length <= @max_chars

    chunks = []
    remaining = section

    while remaining.length > @max_chars
      break_at = remaining.rindex("\n", @max_chars) || @max_chars
      break_at = @max_chars if break_at <= 0
      chunks << remaining[0, break_at].strip
      remaining = remaining[break_at..].strip
    end

    chunks << remaining if remaining.present?
    chunks
  end
end
