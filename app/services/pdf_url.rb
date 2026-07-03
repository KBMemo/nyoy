# frozen_string_literal: true

require "cgi"

module PdfUrl
  module_function

  def blocked?(url)
    return false if url.blank?

    uri = HttpUrl.parse(url)
    path = CGI.unescape(uri.path.to_s).downcase
    return true if path.end_with?(".pdf")
    return true if path.include?(".pdf/")

    query = uri.query.to_s.downcase
    return true if query.include?("filetype=pdf") || query.include?("format=pdf")

    false
  rescue URI::InvalidURIError
    url.to_s.downcase.include?(".pdf")
  end

  def blocked_content_type?(content_type)
    content_type.to_s.downcase.include?("application/pdf")
  end
end
