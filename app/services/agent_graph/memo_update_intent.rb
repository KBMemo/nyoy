# frozen_string_literal: true

module AgentGraph
  module MemoUpdateIntent
    STRONG = [
      /update[_ ]?memo/i,
      /メモ.*(更新|追記|書き換|修正)/,
      /徒然.*(更新|追記|書き換|修正)/,
      /(更新|追記|書き換|修正).*メモ/,
      /(更新|追記|書き換|修正).*徒然/
    ].freeze

    RESEARCH_FRAMING = [
      /調べて/,
      /調査して/,
      /リサーチ/,
      /\bresearch\b/i,
      /出典/,
      /根拠/,
      /事実確認/
    ].freeze

    module_function

    def match?(text)
      decision(text).fetch(:match)
    end

    def decision(text)
      normalized = text.to_s.strip
      return reject("blank") if normalized.blank?

      hits = STRONG.select { |pattern| normalized.match?(pattern) }.map(&:source)
      return reject("no_signal") if hits.empty?
      return reject("defer_research", hits) if research_framed?(normalized)

      accept("strong", hits)
    end

    def research_framed?(text)
      RESEARCH_FRAMING.any? { |pattern| text.match?(pattern) }
    end

    def accept(reason, hits)
      { match: true, reason: reason, hits: hits }
    end

    def reject(reason, hits = [])
      { match: false, reason: reason, hits: hits }
    end
    private_class_method :accept, :reject
  end
end
