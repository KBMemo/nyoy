# frozen_string_literal: true

module TsurezureMemoUrl
  module_function

  def absolute(memo, base_url: NyoyConnectionStore.url(:kbmemo))
    url = memo.is_a?(Hash) ? memo["url"].to_s.strip : memo.to_s.strip
    return url if url.match?(%r{\Ahttps?://}i)

    root = web_root(base_url)
    return url if root.blank?

    return "#{root}#{url}" if url.start_with?("/")

    ref = memo.is_a?(Hash) ? memo["uid"].presence || memo["id"] : nil
    return "#{root}/memos/#{ref}" if ref.present?

    url
  end

  def web_root(base_url)
    base_url.to_s.strip.sub(%r{/api/v1\z}i, "").sub(%r{/\z}, "")
  end
end
