# frozen_string_literal: true

require "uri"

# Normalizes IRIs (e.g. Japanese paths) into ASCII URIs for Ruby's URI parser.
module HttpUrl
  module_function

  def parse(url)
    URI.parse(normalize(url))
  end

  def normalize(url)
    value = url.to_s.strip
    return value if value.ascii_only?

    value.gsub(/[^\u0000-\u007F]/) do |char|
      char.bytes.map { |b| format("%%%02X", b) }.join
    end
  end
end
