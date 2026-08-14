# frozen_string_literal: true

require "uri"

# Normalizes IRIs (e.g. Japanese paths) into ASCII URIs for Ruby's URI parser.
# Also repairs http(s) URLs that local LLMs commonly corrupt in tool-call
# arguments by inserting BPE spaces or replacing `/` with a space.
module HttpUrl
  URL_PATTERN = %r{https?://[^\s<>\]]+}i
  HTTP_PARTS = %r{\A(https?://)([^/?#]*)(/[^?#]*)?(\?[^#]*)?(#.*)?\z}i

  module_function

  def parse(url)
    URI.parse(normalize(url))
  end

  def normalize(url)
    value = repair_tool_call_url(url.to_s.strip)
    return value if value.ascii_only?

    value.gsub(/[^\u0000-\u007F]/) do |char|
      char.bytes.map { |b| format("%%%02X", b) }.join
    end
  end

  def extract_all(text)
    text.to_s.scan(URL_PATTERN).map { |url| url.sub(/[),.]+$/, "") }.uniq
  end

  def recover_from_explicit(url, candidates)
    return nil if Array(candidates).empty?
    return nil unless corrupted_tool_url?(url)

    key = fingerprint(url)
    return nil if key.length < 12

    matches = Array(candidates).map(&:to_s).select { |candidate| fingerprint(candidate) == key }
    matches.first if matches.one?
  end

  def repair_tool_call_url(url)
    value = url.to_s.strip
    return value unless value.match?(/\Ahttps?:\/\//i)
    return value unless value.match?(/[[:space:]]/)

    compacted = value.gsub(/[[:space:]]+/, " ").strip
    match = compacted.match(HTTP_PARTS)
    return compacted.delete(" ") unless match

    scheme = match[1]
    host = match[2].to_s.delete(" ")
    path = repair_path(match[3].to_s.strip)
    query = repair_query(match[4].to_s.delete_prefix("?").strip)
    fragment = match[5].to_s.delete_prefix("#").strip.delete(" ")

    rebuilt = "#{scheme}#{host}#{path}"
    rebuilt += "?#{query}" if match[4]
    rebuilt += "##{fragment}" if match[5]
    rebuilt
  end

  def fingerprint(url)
    url.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def corrupted_tool_url?(url)
    value = url.to_s
    return true if value.match?(/[[:space:]]/)

    URI.parse(value.strip)
    false
  rescue URI::InvalidURIError
    true
  end
  private_class_method :corrupted_tool_url?

  def repair_path(path)
    return path if path.blank?

    value = join_identifier_tokens(collapse_structural_whitespace(path))
    value.gsub(/[[:space:]]+/, "/")
  end
  private_class_method :repair_path

  def repair_query(query)
    return query if query.blank?

    value = join_identifier_tokens(collapse_structural_whitespace(query))
    value.gsub(" ", "%20")
  end
  private_class_method :repair_query

  def collapse_structural_whitespace(value)
    value.gsub(/[[:space:]]*([\/?#&=:._-])[[:space:]]*/, '\1')
  end
  private_class_method :collapse_structural_whitespace

  def join_identifier_tokens(value)
    loop do
      next_value = value.gsub(/([A-Za-z])[[:space:]]+(\d)/, '\1\2')
      next_value.gsub!(/(\d)[[:space:]]+([A-Za-z])/, '\1\2')
      next_value.gsub!(/([a-z])[[:space:]]+([A-Z])/, '\1\2')
      next_value.gsub!(/([A-Z]+)[[:space:]]+([A-Z]+)/, '\1\2')
      next_value.gsub!(/([A-Z][a-z]+)[[:space:]]+([A-Z][a-z]+)/, '\1\2')
      break next_value if next_value == value

      value = next_value
    end
  end
  private_class_method :join_identifier_tokens
end
