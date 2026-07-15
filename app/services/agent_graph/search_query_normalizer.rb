# frozen_string_literal: true

module AgentGraph
  # Turn a chat research question into SearxNG-friendly keyword queries.
  # Prefer "高尾山 景信山 登山道" over "高尾山から景信山への登山道を調べて 出典 根拠".
  class SearchQueryNormalizer
    URL_PATTERN = %r{https?://[^\s<>\]]+}i

    FILLER_PHRASES = [
      /確認してから(?:答えて)?(?:ください|下さい)?/,
      /承認してから/,
      /調べてみて(?:ください|下さい)?/,
      /調べて(?:ください|下さい)?/,
      /調査して(?:ください|下さい)?/,
      /検索して(?:ください|下さい)?/,
      /教えて(?:ください|下さい)?/,
      /答えて(?:ください|下さい)?/,
      /まとめて(?:ください|下さい)?/,
      /について/,
      /に関して/,
      /に関する/,
      /までの(?:道|ルート|コース)?/,
      /からの(?:道|ルート|コース)?/
    ].freeze

    # Splitters between content words (particles / connectives).
    SPLIT_PATTERN = /
      から|への|まで|より|へ|を|に|は|が|も|と|や|で|の|
      [[:space:]　、。！？!?・／\/|｜:：;；]+
    /x

    META_TOKENS = %w[
      出典 根拠 調査 検索 調べ 最新 ニュース 公式 Web ウェブ ネット
      情報 詳細 一次情報 別の視点 確認 承認 ドラフト メモ 徒然
      research source citation evidence
    ].freeze

    MAX_QUERY_CHARS = 80
    MAX_TOKENS = 8

    def self.queries_for(question, replan: false)
      new(question, replan: replan).queries
    end

    def initialize(question, replan: false)
      @question = question.to_s
      @replan = replan
    end

    def queries
      keywords = keyword_tokens
      return [ fallback_query ] if keywords.empty?

      primary = keywords.first(MAX_TOKENS).join(" ").truncate(MAX_QUERY_CHARS)
      list = [ primary ]
      list.concat(expanded_variants(keywords))
      list.concat(replan_variants(keywords)) if @replan
      list.map { |q| q.to_s.strip.truncate(MAX_QUERY_CHARS) }.reject(&:blank?).uniq.first(3)
    end

    private

    def keyword_tokens
      text = @question.dup
      text.gsub!(URL_PATTERN, " ")
      FILLER_PHRASES.each { |pattern| text.gsub!(pattern, " ") }
      text.split(SPLIT_PATTERN)
        .map { |token| token.to_s.strip }
        .reject { |token| drop_token?(token) }
    end

    def drop_token?(token)
      return true if token.blank?
      return true if token.length < 2 && !token.match?(/\A[A-Za-z0-9]+\z/)
      return true if META_TOKENS.any? { |meta| token.casecmp?(meta) }
      return true if token.match?(/\A(ください|下さい|お願い|どうか)\z/)

      false
    end

    def expanded_variants(keywords)
      variants = []
      if keywords.any? { |token| token.match?(/登山道|登山コース|ハイキングコース/) }
        alt = keywords.map { |token| token.gsub(/登山道|登山コース|ハイキングコース/, "登山ルート") }
        variants << alt.first(MAX_TOKENS).join(" ")
      elsif keywords.any? { |token| token.match?(/登山|ハイキング|縦走/) } &&
            keywords.none? { |token| token.match?(/ルート|道|コース|登山道/) }
        variants << (keywords.first(MAX_TOKENS - 1) + [ "登山ルート" ]).join(" ")
      end
      variants
    end

    def replan_variants(keywords)
      base = keywords.first([ MAX_TOKENS - 1, 1 ].max)
      [
        (base + [ "公式" ]).join(" "),
        (base + [ "詳細" ]).join(" ")
      ]
    end

    def fallback_query
      @question.gsub(URL_PATTERN, " ").squish.truncate(MAX_QUERY_CHARS)
    end
  end
end
